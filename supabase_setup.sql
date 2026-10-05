-- Entre páginas · backend seguro para Supabase/Postgres
-- Ejecutar una vez en Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.prompts (
  id int primary key,
  title text not null,
  description text not null
);

insert into public.prompts(id,title,description) values
(1,'Hay vida ahí','En la portada aparece algo vivo que no sea una persona.'),
(2,'Color impuesto','La otra persona elige un color. Ese color debe dominar la portada.'),
(3,'Amor a primera portada','Elige únicamente por la portada. No puedes leer la sinopsis hasta después de decidir.'),
(4,'Algo fuera de lugar','La portada tiene un objeto extraño, inesperado o que te haga preguntarte qué hace ahí.'),
(5,'Sin personas','Ni una cara, silueta, mano ni cuerpo humano en la portada.'),
(6,'Tres palabras','El título tiene exactamente tres palabras.'),
(7,'Una palabra','Todo el título es una sola palabra.'),
(8,'¿Qué significa eso?','Un título que, sin conocer la historia, no entiendas del todo.'),
(9,'Palabra secreta','La otra persona elige una palabra antes de empezar la búsqueda. Hay que encontrarla en el título.'),
(10,'De la A a la Z','Gira una ruleta de letras. El título tiene que empezar por la letra que salga.'),
(11,'El estante decide','En una librería o biblioteca, genera un número aleatorio del 1 al 5. Ese número determina el estante empezando desde abajo.'),
(12,'Una página, una oportunidad','Abre un candidato al azar y lee una sola página. No la sinopsis. Esa página decide.'),
(13,'Recomendación humana','Pregúntale a una persona qué libro deberías leer. No vale Google ni ChatGPT.'),
(14,'El olvidado','Un libro que lleves mucho tiempo diciendo que algún día vas a leer.'),
(15,'La contraportada prohibida','Puedes investigar autor, género y portada, pero no puedes leer la sinopsis antes de escogerlo.'),
(16,'Nunca hemos estado ahí','El autor es de un país en el que ninguna de las dos haya estado nunca.'),
(17,'Originalmente no lo entenderíamos','El libro fue escrito originalmente en un idioma que ninguna de las dos habla.'),
(18,'Viaje literario','Primero elijan al azar un país. Después hay que encontrar un libro escrito por alguien de ese país.'),
(19,'Antes de nosotras','Publicado antes de que cualquiera de las dos naciera.'),
(20,'El otro lado de la historia','Un libro ambientado principalmente en un lugar sobre el que ninguna de las dos sepa demasiado.'),
(21,'Rabbit hole','Tiene que contener algo que te haga pensar: “¿Cómo nunca había oído hablar de esto?”.'),
(22,'Algo real escondido dentro','Puede ser ficción, pero debe contener un elemento real que den ganas de investigar después.'),
(23,'Profesión ajena','El personaje principal tiene un trabajo que ninguna de las dos haya tenido ni estudiado.'),
(24,'Una obsesión muy específica','Encuentra un libro sobre algo absurdamente específico. Cuanto más difícil sea explicar por qué existe un libro entero sobre eso, mejor.'),
(25,'Fuera de personaje','Algo que normalmente jamás escogerías.'),
(26,'Necesito esto ahora','Elige el libro que sientas que necesitas leer en ese momento. Sin más condiciones.'),
(27,'Una emoción primero','Antes de buscar el libro, escribe una emoción que quieras sentir. Después busca el libro.'),
(28,'Confía en mí','Elige un libro para la otra persona basándote en sus gustos. No tienes que justificar la elección.'),
(29,'Cambio de estantería','Elige un libro que represente muy bien tus propios gustos, pero que creas que la otra probablemente nunca escogería por su cuenta.'),
(30,'Te vi aquí','Elige un libro porque algo en él —el título, la portada, la historia, una frase o un detalle difícil de explicar— te resultó extrañamente familiar. La razón se revela solo al terminarlo.')
on conflict (id) do update set title=excluded.title, description=excluded.description;

create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Entre páginas',
  current_turn_user uuid references auth.users(id),
  round int not null default 1,
  pending_prompt int references public.prompts(id),
  pending_mode text check (pending_mode in ('spin','why')),
  created_at timestamptz not null default now()
);

create table if not exists public.club_members (
  club_id uuid references public.clubs(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  display_name text not null,
  turn_order int not null check (turn_order in (1,2)),
  primary key(club_id,user_id),
  unique(club_id,turn_order)
);

create table if not exists public.club_prompts (
  club_id uuid references public.clubs(id) on delete cascade,
  prompt_id int references public.prompts(id),
  used boolean not null default false,
  used_by uuid references auth.users(id),
  used_at timestamptz,
  primary key(club_id,prompt_id)
);

create table if not exists public.jokers (
  club_id uuid references public.clubs(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  nope_used boolean not null default false,
  why_used boolean not null default false,
  decide_used boolean not null default false,
  primary key(club_id,user_id)
);

create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references public.clubs(id) on delete cascade,
  round int not null,
  selected_by uuid references auth.users(id),
  title text not null,
  author text not null,
  prompt_id int references public.prompts(id),
  selection_mode text not null check(selection_mode in ('spin','why')),
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id bigint generated always as identity primary key,
  club_id uuid references public.clubs(id) on delete cascade,
  actor uuid references auth.users(id),
  event_type text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.is_member(p_club uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.club_members where club_id=p_club and user_id=p_user);
$$;

-- Funciones de setup: se ejecutan SOLO desde SQL Editor con el rol propietario.
create or replace function public.create_reading_club(p_user1 uuid,p_name1 text,p_user2 uuid,p_name2 text)
returns uuid language plpgsql security definer set search_path=public as $$
declare c uuid;
begin
  if p_user1 is null or p_user2 is null or p_user1=p_user2 then
    raise exception 'Two different users are required';
  end if;
  insert into public.clubs(name,current_turn_user) values('Entre páginas',p_user1) returning id into c;
  insert into public.club_members(club_id,user_id,display_name,turn_order)
    values(c,p_user1,p_name1,1),(c,p_user2,p_name2,2);
  insert into public.club_prompts(club_id,prompt_id) select c,id from public.prompts;
  insert into public.jokers(club_id,user_id) values(c,p_user1),(c,p_user2);
  insert into public.events(club_id,event_type,detail)
    values(c,'season_started',jsonb_build_object('first_turn',p_name1));
  return c;
end $$;

create or replace function public.create_reading_club_by_email(
  p_email1 text,p_name1 text,p_email2 text,p_name2 text
)
returns uuid language plpgsql security definer set search_path=public as $$
declare u1 uuid; u2 uuid;
begin
  select id into u1 from auth.users where lower(email)=lower(trim(p_email1)) limit 1;
  select id into u2 from auth.users where lower(email)=lower(trim(p_email2)) limit 1;
  if u1 is null then raise exception 'First email not found in Auth users'; end if;
  if u2 is null then raise exception 'Second email not found in Auth users'; end if;
  return public.create_reading_club(u1,p_name1,u2,p_name2);
end $$;

create or replace function public.spin_wheel(p_club uuid)
returns table(id int,title text,description text) language plpgsql security definer set search_path=public as $$
declare c public.clubs%rowtype; chosen int;
begin
  if not public.is_member(p_club) then raise exception 'Not a member'; end if;
  select * into c from public.clubs where id=p_club for update;
  if not found then raise exception 'Club not found'; end if;
  if c.current_turn_user<>auth.uid() or c.pending_mode is not null then
    raise exception 'Not your turn or action pending';
  end if;
  select cp.prompt_id into chosen
    from public.club_prompts cp
    where cp.club_id=p_club and not cp.used
    order by random() limit 1 for update;
  if chosen is null then raise exception 'No prompts remaining'; end if;
  update public.club_prompts set used=true,used_by=auth.uid(),used_at=now()
    where club_id=p_club and prompt_id=chosen;
  update public.clubs set pending_prompt=chosen,pending_mode='spin' where id=p_club;
  insert into public.events(club_id,actor,event_type,detail)
    values(p_club,auth.uid(),'spin',jsonb_build_object('prompt_id',chosen));
  return query select p.id,p.title,p.description from public.prompts p where p.id=chosen;
end $$;

create or replace function public.use_nope_and_spin(p_club uuid)
returns table(id int,title text,description text) language plpgsql security definer set search_path=public as $$
declare c public.clubs%rowtype; old_prompt int; chosen int; already boolean;
begin
  if not public.is_member(p_club) then raise exception 'Not a member'; end if;
  select * into c from public.clubs where id=p_club for update;
  if not found or c.current_turn_user<>auth.uid() or c.pending_mode<>'spin' or c.pending_prompt is null then
    raise exception 'NOPE requires your pending spin';
  end if;
  old_prompt:=c.pending_prompt;
  select nope_used into already from public.jokers
    where club_id=p_club and user_id=auth.uid() for update;
  if coalesce(already,true) then raise exception 'NOPE already used'; end if;
  update public.jokers set nope_used=true where club_id=p_club and user_id=auth.uid();
  insert into public.events(club_id,actor,event_type,detail)
    values(p_club,auth.uid(),'nope',jsonb_build_object('discarded_prompt_id',old_prompt));
  select cp.prompt_id into chosen
    from public.club_prompts cp
    where cp.club_id=p_club and not cp.used
    order by random() limit 1 for update;
  if chosen is null then raise exception 'No prompts remaining'; end if;
  update public.club_prompts set used=true,used_by=auth.uid(),used_at=now()
    where club_id=p_club and prompt_id=chosen;
  update public.clubs set pending_prompt=chosen,pending_mode='spin' where id=p_club;
  insert into public.events(club_id,actor,event_type,detail)
    values(p_club,auth.uid(),'spin_after_nope',jsonb_build_object('prompt_id',chosen));
  return query select p.id,p.title,p.description from public.prompts p where p.id=chosen;
end $$;

create or replace function public.use_why(p_club uuid)
returns void language plpgsql security definer set search_path=public as $$
declare c public.clubs%rowtype; already boolean;
begin
  if not public.is_member(p_club) then raise exception 'Not a member'; end if;
  select * into c from public.clubs where id=p_club for update;
  if not found or c.current_turn_user<>auth.uid() or c.pending_mode is not null then
    raise exception 'Not your turn or action pending';
  end if;
  select why_used into already from public.jokers
    where club_id=p_club and user_id=auth.uid() for update;
  if coalesce(already,true) then raise exception 'PORQUE QUIERO already used'; end if;
  update public.jokers set why_used=true where club_id=p_club and user_id=auth.uid();
  update public.clubs set pending_prompt=null,pending_mode='why' where id=p_club;
  insert into public.events(club_id,actor,event_type) values(p_club,auth.uid(),'why');
end $$;

create or replace function public.use_decide(p_club uuid)
returns void language plpgsql security definer set search_path=public as $$
declare c public.clubs%rowtype; nxt uuid; already boolean;
begin
  if not public.is_member(p_club) then raise exception 'Not a member'; end if;
  select * into c from public.clubs where id=p_club for update;
  if not found or c.current_turn_user<>auth.uid() or c.pending_mode is not null then
    raise exception 'Not your turn or action pending';
  end if;
  select decide_used into already from public.jokers
    where club_id=p_club and user_id=auth.uid() for update;
  if coalesce(already,true) then raise exception 'TÚ DECIDES already used'; end if;
  select user_id into nxt from public.club_members
    where club_id=p_club and user_id<>auth.uid() order by turn_order limit 1;
  if nxt is null then raise exception 'Other member not found'; end if;
  update public.jokers set decide_used=true where club_id=p_club and user_id=auth.uid();
  update public.clubs set current_turn_user=nxt where id=p_club;
  insert into public.events(club_id,actor,event_type,detail)
    values(p_club,auth.uid(),'decide',jsonb_build_object('new_turn',nxt));
end $$;

create or replace function public.save_book(p_club uuid,p_title text,p_author text)
returns void language plpgsql security definer set search_path=public as $$
declare c public.clubs%rowtype; nxt uuid;
begin
  if trim(coalesce(p_title,''))='' or trim(coalesce(p_author,''))='' then
    raise exception 'Title and author required';
  end if;
  if not public.is_member(p_club) then raise exception 'Not a member'; end if;
  select * into c from public.clubs where id=p_club for update;
  if not found or c.current_turn_user<>auth.uid() or c.pending_mode is null then
    raise exception 'Not your turn or no selection pending';
  end if;
  insert into public.books(club_id,round,selected_by,title,author,prompt_id,selection_mode)
    values(p_club,c.round,auth.uid(),trim(p_title),trim(p_author),c.pending_prompt,c.pending_mode);
  select user_id into nxt from public.club_members
    where club_id=p_club and user_id<>auth.uid() order by turn_order limit 1;
  if nxt is null then raise exception 'Other member not found'; end if;
  update public.clubs
    set current_turn_user=nxt,round=round+1,pending_prompt=null,pending_mode=null
    where id=p_club;
  insert into public.events(club_id,actor,event_type,detail)
    values(p_club,auth.uid(),'book_saved',jsonb_build_object('title',trim(p_title),'author',trim(p_author),'round',c.round));
end $$;

-- RLS: las dos integrantes pueden leer; ninguna puede mutar tablas directamente.
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_prompts enable row level security;
alter table public.jokers enable row level security;
alter table public.books enable row level security;
alter table public.events enable row level security;
alter table public.prompts enable row level security;

drop policy if exists "prompts readable" on public.prompts;
drop policy if exists "member reads club" on public.clubs;
drop policy if exists "member reads members" on public.club_members;
drop policy if exists "member reads club prompts" on public.club_prompts;
drop policy if exists "member reads jokers" on public.jokers;
drop policy if exists "member reads books" on public.books;
drop policy if exists "member reads events" on public.events;

create policy "prompts readable" on public.prompts for select to authenticated using (true);
create policy "member reads club" on public.clubs for select to authenticated using (public.is_member(id));
create policy "member reads members" on public.club_members for select to authenticated using (public.is_member(club_id));
create policy "member reads club prompts" on public.club_prompts for select to authenticated using (public.is_member(club_id));
create policy "member reads jokers" on public.jokers for select to authenticated using (public.is_member(club_id));
create policy "member reads books" on public.books for select to authenticated using (public.is_member(club_id));
create policy "member reads events" on public.events for select to authenticated using (public.is_member(club_id));

revoke insert,update,delete on public.clubs,public.club_members,public.club_prompts,public.jokers,public.books,public.events from authenticated,anon;
grant select on public.prompts,public.clubs,public.club_members,public.club_prompts,public.jokers,public.books,public.events to authenticated;

-- Quita el EXECUTE implícito de PUBLIC. Solo las acciones de juego quedan disponibles para cuentas autenticadas.
revoke all on function public.is_member(uuid,uuid) from public,anon;
revoke all on function public.create_reading_club(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.create_reading_club_by_email(text,text,text,text) from public,anon,authenticated;
revoke all on function public.spin_wheel(uuid) from public,anon;
revoke all on function public.use_nope_and_spin(uuid) from public,anon;
revoke all on function public.use_why(uuid) from public,anon;
revoke all on function public.use_decide(uuid) from public,anon;
revoke all on function public.save_book(uuid,text,text) from public,anon;

grant execute on function public.is_member(uuid,uuid) to authenticated;
grant execute on function public.spin_wheel(uuid),public.use_nope_and_spin(uuid),public.use_why(uuid),public.use_decide(uuid),public.save_book(uuid,text,text) to authenticated;

-- SETUP FINAL (ejecutar DESPUÉS de crear las dos cuentas en Authentication > Users):
-- select public.create_reading_club_by_email(
--   'TU_CORREO','María',
--   'CORREO_PROFE','Profe'
-- );
-- La función devuelve el UUID del club. No hace falta copiarlo al frontend.
