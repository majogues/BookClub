# Entre páginas — login por PIN

Esta versión no usa emails ni cuentas de Supabase Auth. Usa dos perfiles internos (`María` y `Profe`) protegidos por PIN.

1. Ejecuta `supabase_pin_setup.sql` completo en Supabase SQL Editor.
2. Después ejecuta UNA sola vez, cambiando los PIN:

```sql
select public.setup_reading_club('María','1234','Profe','5678');
```

Usa PIN distintos y no uses los del ejemplo.

3. En `config.js` pega únicamente:
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Nunca pegues una secret key/service-role key en el frontend.

4. Publica `index.html`, `app-online.js` y `config.js` juntos.
