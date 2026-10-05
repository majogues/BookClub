# Entre páginas — versión online

Mini-app compartida para el club de lectura. El frontend puede publicarse con GitHub Pages y el estado vive en Supabase.

## Qué queda protegido en servidor
- Turno actual.
- Prompts ya usados: no vuelven a la ruleta.
- NOPE, PORQUE QUIERO y TÚ DECIDES: una vez por persona.
- Prompt pendiente y libro elegido.
- Historial con actor y fecha/hora.
- No existe botón de reset en la app.
- Las tablas no aceptan escrituras directas de usuarios; las decisiones pasan por funciones de servidor.

## 1. Crear Supabase
1. Crea un proyecto en https://supabase.com/.
2. SQL Editor → New query.
3. Pega y ejecuta `supabase_setup.sql`.
4. Authentication → Users → Add user. Crea las dos cuentas (una para María y otra para Profe) con email y contraseña.
5. Vuelve a SQL Editor y ejecuta:

```sql
select public.create_reading_club_by_email(
  'TU_CORREO','María',
  'CORREO_PROFE','Profe'
);
```

6. En Supabase busca Project URL y Publishable key.
7. Edita `config.js` y reemplaza los dos placeholders. Nunca pongas una secret/service-role key en este archivo.

## 2. Probar antes de publicar
Abre la carpeta con un servidor estático local. Por ejemplo, con Python:

```bash
python -m http.server 8080
```

Luego abre `http://localhost:8080`.

## 3. Publicar en GitHub Pages
1. Crea un repositorio público, por ejemplo `entre-paginas`.
2. Sube el contenido de esta carpeta a la raíz de `main`.
3. Repository Settings → Pages.
4. En Build and deployment, Source → **Deploy from a branch**.
5. Branch → `main`, folder → `/(root)` y guarda.
6. GitHub mostrará una URL parecida a `https://TU_USUARIO.github.io/entre-paginas/`.

El repositorio puede ser público porque `config.js` solo contiene la URL del proyecto y una **publishable key**. La seguridad de los datos está en Supabase Row Level Security y en las funciones del servidor. No publiques una secret key.

## Archivos
- `index.html`: interfaz.
- `app-online.js`: login, sincronización, ruleta y comodines.
- `config.js`: Project URL + Publishable key.
- `supabase_setup.sql`: base de datos, RLS y funciones atómicas.
- `.nojekyll`: evita procesamiento innecesario de Jekyll en GitHub Pages.
