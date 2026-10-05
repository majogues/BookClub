-- Entre páginas · versión SIN correo: perfiles + PIN privado creado en primer acceso
-- IMPORTANTE: este script REEMPLAZA el esquema anterior. Úsalo ahora, antes de tener datos reales.
-- Ejecutar completo una vez en Supabase SQL Editor.

create extension if not exists pgcrypto;

-- Limpiar versión anterior (todavía no hay datos reales)
drop function if exists public.create_reading_club_by_email(text,text,text,text) cascade;
drop function if exists public.setup_reading_club(text,text,text,text) cascade;
drop function if exists public.setup_reading_club(text,text) cascade;
drop function if exists public.profile_status(text) cascade;
drop function if exists public.initialize_player_pin(text,text) cascade;
drop function if exists public.login_player(text,text) cascade;
drop function if exists public.session_profile(text) cascade;
drop function if exists public.logout_player(text) cascade;
drop function if exists public.read_club_state(text) cascade;
drop function if exists public.create_reading_club(uuid,text,uuid,text) cascade;
drop function if exists public.spin_wheel(uuid) cascade;
drop function if exists public.use_nope_and_spin(uuid) cascade;
drop function if exists public.use_why(uuid) cascade;
drop function if exists public.use_decide(uuid) cascade;
drop function if exists public.save_book(uuid,text,text) cascade;
drop function if exists public.is_member(uuid,uuid) cascade;

drop table if exists public.events cascade;
drop table if exists public.books cascade;
drop table if exists public.jokers cascade;
drop table if exists public.club_prompts cascade;
drop table if exists public.club_members cascade;
drop table if exists public.clubs cascade;
drop table if exists public.prompts cascade;
drop table if exists public.player_sessions cascade;
drop table if exists public.players cascade;

create table public.prompts (
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
(30,'Te vi aquí','Elige un libro porque algo en él —el título, la portada, la historia, una frase o un detalle difícil de explicar— te resultó extrañamente familiar. La razón se revela solo al terminarlo.');

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Entre páginas',
  current_turn_player uuid,
  round int not null default 1,
  pending_prompt int references public.prompts(id),
  pending_mode text check (pending_mode in ('spin','why')),
  created_at timestamptz not null default now()
);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  display_name text not null,
  turn_order int not null check (turn_order in (1,2)),
  pin_hash text,
  pin_initialized boolean not null default false,
  unique(club_id,turn_order),
  unique(club_id,display_name)
);
alter table public.clubs add constraint clubs_turn_player_fk foreign key(current_turn_player) references public.players(id);

create table public.player_sessions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '180 days')
);

create table public.club_prompts (
  club_id uuid references public.clubs(id) on delete cascade,
  prompt_id int references public.prompts(id),
  used boolean not null default false,
  used_by uuid references public.players(id),
  used_at timestamptz,
  primary key(club_id,prompt_id)
);

create table public.jokers (
  club_id uuid references public.clubs(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,
  nope_used boolean not null default false,
  why_used boolean not null default false,
  decide_used boolean not null default false,
  primary key(club_id,player_id)
);

create table public.books (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references public.clubs(id) on delete cascade,
  round int not null,
  selected_by uuid references public.players(id),
  title text not null,
  author text not null,
  prompt_id int references public.prompts(id),
  selection_mode text not null check(selection_mode in ('spin','why')),
  created_at timestamptz not null default now()
);

create table public.events (
  id bigint generated always as identity primary key,
  club_id uuid references public.clubs(id) on delete cascade,
  actor uuid references public.players(id),
  event_type text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Ninguna tabla se consulta directamente desde el navegador.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Helper privado: valida token de sesión y devuelve player_id.
create or replace function public._player_from_session(p_session text)
returns uuid language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
  if p_session is null or length(p_session) < 32 then raise exception 'Sesión inválida'; end if;
  select s.player_id into pid
  from public.player_sessions s
  where s.token_hash = digest(p_session,'sha256') and s.expires_at > now()
  limit 1;
  if pid is null then raise exception 'Sesión vencida o inválida'; end if;
  return pid;
end $$;
revoke all on function public._player_from_session(text) from public, anon, authenticated;

-- SETUP: crea el club y los dos perfiles, PERO SIN PIN.
-- Ejecutar SOLO desde SQL Editor una vez, después de este script.
create or replace function public.setup_reading_club(
  p_name1 text, p_name2 text
) returns uuid language plpgsql security definer set search_path=public as $$
declare c uuid; u1 uuid; u2 uuid;
begin
  if length(trim(p_name1))<1 or length(trim(p_name2))<1 then raise exception 'Los nombres son obligatorios'; end if;
  if lower(trim(p_name1))=lower(trim(p_name2)) then raise exception 'Los nombres deben ser diferentes'; end if;

  insert into public.clubs(name) values('Entre páginas') returning id into c;
  insert into public.players(club_id,display_name,turn_order)
    values(c,trim(p_name1),1) returning id into u1;
  insert into public.players(club_id,display_name,turn_order)
    values(c,trim(p_name2),2) returning id into u2;
  update public.clubs set current_turn_player=u1 where id=c;
  insert into public.club_prompts(club_id,prompt_id) select c,id from public.prompts;
  insert into public.jokers(club_id,player_id) values(c,u1),(c,u2);
  insert into public.events(club_id,event_type,detail)
    values(c,'season_started',jsonb_build_object('first_turn',trim(p_name1)));
  return c;
end $$;
revoke all on function public.setup_reading_club(text,text) from public, anon, authenticated;

-- La app puede preguntar si un perfil ya creó su PIN, pero nunca recibe el PIN ni su hash.
create or replace function public.profile_status(p_name text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.players%rowtype;
begin
  select * into p from public.players
  where lower(display_name)=lower(trim(p_name))
  order by turn_order limit 1;
  if not found then raise exception 'Perfil no encontrado'; end if;
  return jsonb_build_object('display_name',p.display_name,'pin_initialized',p.pin_initialized);
end $$;

-- PRIMER ACCESO: cada persona crea su propio PIN una sola vez.
create or replace function public.initialize_player_pin(p_name text, p_pin text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.players%rowtype; tok text;
begin
  if p_pin is null or length(p_pin)<6 then raise exception 'El PIN debe tener al menos 6 caracteres'; end if;
  select * into p from public.players
    where lower(display_name)=lower(trim(p_name))
    order by turn_order limit 1
    for update;
  if not found then raise exception 'Perfil no encontrado'; end if;
  if p.pin_initialized or p.pin_hash is not null then raise exception 'Este perfil ya creó su PIN'; end if;

  update public.players
    set pin_hash=crypt(p_pin,gen_salt('bf',10)), pin_initialized=true
    where id=p.id;

  tok := encode(gen_random_bytes(32),'hex');
  insert into public.player_sessions(player_id,token_hash) values(p.id,digest(tok,'sha256'));
  return jsonb_build_object('session',tok,'player_id',p.id,'display_name',p.display_name,'club_id',p.club_id);
end $$;

-- Accesos posteriores. Devuelve un token aleatorio; nunca devuelve el PIN ni su hash.
create or replace function public.login_player(p_name text, p_pin text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.players%rowtype; tok text;
begin
  select * into p from public.players
    where lower(display_name)=lower(trim(p_name))
      and pin_initialized=true
      and pin_hash = crypt(p_pin,pin_hash)
    order by turn_order limit 1;
  if not found then raise exception 'Nombre o PIN incorrecto'; end if;
  tok := encode(gen_random_bytes(32),'hex');
  delete from public.player_sessions where player_id=p.id and expires_at <= now();
  insert into public.player_sessions(player_id,token_hash) values(p.id,digest(tok,'sha256'));
  return jsonb_build_object('session',tok,'player_id',p.id,'display_name',p.display_name,'club_id',p.club_id);
end $$;

create or replace function public.session_profile(p_session text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid; p public.players%rowtype;
begin
  pid:=public._player_from_session(p_session);
  select * into p from public.players where id=pid;
  return jsonb_build_object('player_id',p.id,'display_name',p.display_name,'club_id',p.club_id);
end $$;

create or replace function public.logout_player(p_session text)
returns void language plpgsql security definer set search_path=public as $$
begin
  delete from public.player_sessions where token_hash=digest(p_session,'sha256');
end $$;

create or replace function public.read_club_state(p_session text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; result jsonb;
begin
  pid:=public._player_from_session(p_session);
  select club_id into cid from public.players where id=pid;
  select jsonb_build_object(
    'me', (select jsonb_build_object('player_id',p.id,'display_name',p.display_name,'turn_order',p.turn_order) from public.players p where p.id=pid),
    'club', (select jsonb_build_object('id',c.id,'name',c.name,'current_turn_player',c.current_turn_player,'round',c.round,'pending_prompt',c.pending_prompt,'pending_mode',c.pending_mode) from public.clubs c where c.id=cid),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'display_name',p.display_name,'turn_order',p.turn_order) order by p.turn_order),'[]'::jsonb) from public.players p where p.club_id=cid),
    'prompts', (select coalesce(jsonb_agg(to_jsonb(pr) order by pr.id),'[]'::jsonb) from public.prompts pr),
    'clubPrompts', (select coalesce(jsonb_agg(jsonb_build_object('prompt_id',cp.prompt_id,'used',cp.used,'used_by',cp.used_by,'used_at',cp.used_at)),'[]'::jsonb) from public.club_prompts cp where cp.club_id=cid),
    'jokers', (select coalesce(jsonb_agg(jsonb_build_object('player_id',j.player_id,'nope_used',j.nope_used,'why_used',j.why_used,'decide_used',j.decide_used)),'[]'::jsonb) from public.jokers j where j.club_id=cid),
    'events', (select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (select e.created_at, jsonb_build_object('id',e.id,'actor',e.actor,'event_type',e.event_type,'detail',e.detail,'created_at',e.created_at) obj from public.events e where e.club_id=cid order by e.created_at desc limit 100) x)
  ) into result;
  return result;
end $$;

create or replace function public.spin_wheel(p_session text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; c public.clubs%rowtype; chosen int; pr public.prompts%rowtype;
begin
  pid:=public._player_from_session(p_session); select club_id into cid from public.players where id=pid;
  select * into c from public.clubs where id=cid for update;
  if c.current_turn_player<>pid or c.pending_mode is not null then raise exception 'No es tu turno o hay una elección pendiente'; end if;
  select cp.prompt_id into chosen from public.club_prompts cp where cp.club_id=cid and not cp.used order by random() limit 1 for update;
  if chosen is null then raise exception 'No quedan prompts'; end if;
  update public.club_prompts set used=true,used_by=pid,used_at=now() where club_id=cid and prompt_id=chosen;
  update public.clubs set pending_prompt=chosen,pending_mode='spin' where id=cid;
  insert into public.events(club_id,actor,event_type,detail) values(cid,pid,'spin',jsonb_build_object('prompt_id',chosen));
  select * into pr from public.prompts where id=chosen;
  return jsonb_build_object('id',pr.id,'title',pr.title,'description',pr.description);
end $$;

create or replace function public.use_nope_and_spin(p_session text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; c public.clubs%rowtype; old_prompt int; chosen int; already boolean; pr public.prompts%rowtype;
begin
  pid:=public._player_from_session(p_session); select club_id into cid from public.players where id=pid;
  select * into c from public.clubs where id=cid for update;
  if c.current_turn_player<>pid or c.pending_mode<>'spin' or c.pending_prompt is null then raise exception 'NOPE requiere un prompt pendiente de tu turno'; end if;
  old_prompt:=c.pending_prompt;
  select nope_used into already from public.jokers where club_id=cid and player_id=pid for update;
  if coalesce(already,true) then raise exception 'Ya usaste NOPE'; end if;
  update public.jokers set nope_used=true where club_id=cid and player_id=pid;
  insert into public.events(club_id,actor,event_type,detail) values(cid,pid,'nope',jsonb_build_object('discarded_prompt_id',old_prompt));
  select cp.prompt_id into chosen from public.club_prompts cp where cp.club_id=cid and not cp.used order by random() limit 1 for update;
  if chosen is null then raise exception 'No quedan prompts para volver a girar'; end if;
  update public.club_prompts set used=true,used_by=pid,used_at=now() where club_id=cid and prompt_id=chosen;
  update public.clubs set pending_prompt=chosen,pending_mode='spin' where id=cid;
  insert into public.events(club_id,actor,event_type,detail) values(cid,pid,'spin_after_nope',jsonb_build_object('prompt_id',chosen));
  select * into pr from public.prompts where id=chosen;
  return jsonb_build_object('id',pr.id,'title',pr.title,'description',pr.description);
end $$;

create or replace function public.use_why(p_session text)
returns void language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; c public.clubs%rowtype; already boolean;
begin
  pid:=public._player_from_session(p_session); select club_id into cid from public.players where id=pid;
  select * into c from public.clubs where id=cid for update;
  if c.current_turn_player<>pid or c.pending_mode is not null then raise exception 'No puedes usar este comodín ahora'; end if;
  select why_used into already from public.jokers where club_id=cid and player_id=pid for update;
  if coalesce(already,true) then raise exception 'Ya usaste PORQUE QUIERO'; end if;
  update public.jokers set why_used=true where club_id=cid and player_id=pid;
  update public.clubs set pending_prompt=null,pending_mode='why' where id=cid;
  insert into public.events(club_id,actor,event_type) values(cid,pid,'why');
end $$;

create or replace function public.use_decide(p_session text)
returns void language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; c public.clubs%rowtype; already boolean; nextp uuid;
begin
  pid:=public._player_from_session(p_session); select club_id into cid from public.players where id=pid;
  select * into c from public.clubs where id=cid for update;
  if c.current_turn_player<>pid or c.pending_mode is not null then raise exception 'No puedes ceder el turno ahora'; end if;
  select decide_used into already from public.jokers where club_id=cid and player_id=pid for update;
  if coalesce(already,true) then raise exception 'Ya usaste TÚ DECIDES'; end if;
  select id into nextp from public.players where club_id=cid and id<>pid limit 1;
  update public.jokers set decide_used=true where club_id=cid and player_id=pid;
  update public.clubs set current_turn_player=nextp where id=cid;
  insert into public.events(club_id,actor,event_type,detail) values(cid,pid,'decide',jsonb_build_object('new_turn',nextp));
end $$;

create or replace function public.save_book(p_session text,p_title text,p_author text)
returns void language plpgsql security definer set search_path=public as $$
declare pid uuid; cid uuid; c public.clubs%rowtype; nextp uuid;
begin
  pid:=public._player_from_session(p_session); select club_id into cid from public.players where id=pid;
  select * into c from public.clubs where id=cid for update;
  if c.current_turn_player<>pid or c.pending_mode is null then raise exception 'No hay una elección pendiente de tu turno'; end if;
  if length(trim(p_title))<1 or length(trim(p_author))<1 then raise exception 'Título y autor son obligatorios'; end if;
  insert into public.books(club_id,round,selected_by,title,author,prompt_id,selection_mode)
    values(cid,c.round,pid,trim(p_title),trim(p_author),case when c.pending_mode='spin' then c.pending_prompt else null end,c.pending_mode);
  insert into public.events(club_id,actor,event_type,detail)
    values(cid,pid,'book_saved',jsonb_build_object('title',trim(p_title),'author',trim(p_author),'round',c.round));
  select id into nextp from public.players where club_id=cid and id<>pid limit 1;
  update public.clubs set current_turn_player=nextp, round=round+1, pending_prompt=null,pending_mode=null where id=cid;
end $$;

-- Solo estas funciones son accesibles desde la web con la publishable key.
grant execute on function public.profile_status(text) to anon, authenticated;
grant execute on function public.initialize_player_pin(text,text) to anon, authenticated;
grant execute on function public.login_player(text,text) to anon, authenticated;
grant execute on function public.session_profile(text) to anon, authenticated;
grant execute on function public.logout_player(text) to anon, authenticated;
grant execute on function public.read_club_state(text) to anon, authenticated;
grant execute on function public.spin_wheel(text) to anon, authenticated;
grant execute on function public.use_nope_and_spin(text) to anon, authenticated;
grant execute on function public.use_why(text) to anon, authenticated;
grant execute on function public.use_decide(text) to anon, authenticated;
grant execute on function public.save_book(text,text,text) to anon, authenticated;

-- Al terminar este script, ejecuta UNA VEZ para crear solo los perfiles (SIN PIN):
-- select public.setup_reading_club('María','Profe');
-- Después, cada una abrirá la web y creará su propio PIN en su primer acceso.
