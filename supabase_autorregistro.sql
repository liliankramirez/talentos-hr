-- TalentOS HR · Autorregistro de candidatos (versión 1.3)
-- Se ejecuta UNA sola vez en Supabase → SQL Editor. Puede ejecutarse de nuevo sin dañar nada.
--
-- Qué crea:
--   1. talentos_convocatorias: lo que el candidato ve al abrir el enlace (cargo, responsable de los datos,
--      canal de contacto y texto de autorización). El público solo puede LEER las que están activas.
--   2. talentos_postulaciones: lo que el candidato envía. El público solo puede INSERTAR;
--      no puede leer, modificar ni borrar nada. Solo la dueña de la convocatoria las ve y las borra.

-- ---------------------------------------------------------------------------------------------
-- 1. Convocatorias
-- ---------------------------------------------------------------------------------------------
create table if not exists public.talentos_convocatorias (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  vacancy_id  text        not null check (char_length(vacancy_id) between 1 and 80),
  titulo      text        not null check (char_length(titulo) between 2 and 120),
  detalle     text        not null default '' check (char_length(detalle) <= 600),
  responsable text        not null check (char_length(responsable) between 2 and 160),
  contacto    text        not null check (char_length(contacto) between 5 and 160),
  aviso       text        not null check (char_length(aviso) between 50 and 4000),
  activa      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, vacancy_id)
);

alter table public.talentos_convocatorias enable row level security;

drop policy if exists "conv_publico_lee_activas" on public.talentos_convocatorias;
drop policy if exists "conv_duena_lee"           on public.talentos_convocatorias;
drop policy if exists "conv_duena_crea"          on public.talentos_convocatorias;
drop policy if exists "conv_duena_actualiza"     on public.talentos_convocatorias;
drop policy if exists "conv_duena_borra"         on public.talentos_convocatorias;

create policy "conv_publico_lee_activas" on public.talentos_convocatorias for select to anon          using (activa);
create policy "conv_duena_lee"           on public.talentos_convocatorias for select to authenticated using (auth.uid() = user_id);
create policy "conv_duena_crea"          on public.talentos_convocatorias for insert to authenticated with check (auth.uid() = user_id);
create policy "conv_duena_actualiza"     on public.talentos_convocatorias for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "conv_duena_borra"         on public.talentos_convocatorias for delete to authenticated using (auth.uid() = user_id);

revoke all on public.talentos_convocatorias from anon, authenticated;
grant select (id, titulo, detalle, responsable, contacto, aviso, activa) on public.talentos_convocatorias to anon;
grant select, insert, update, delete on public.talentos_convocatorias to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. Postulaciones
-- ---------------------------------------------------------------------------------------------
create table if not exists public.talentos_postulaciones (
  id              uuid        primary key default gen_random_uuid(),
  convocatoria_id uuid        not null references public.talentos_convocatorias (id) on delete cascade,
  user_id         uuid        references auth.users (id) on delete cascade,
  nombre          text        not null check (char_length(nombre) between 3 and 120),
  celular         text        not null check (celular ~ '^[0-9+ ]{7,20}$'),
  zona            text        not null default '' check (char_length(zona) <= 120),
  experiencia     text        not null default '' check (char_length(experiencia) <= 600),
  disponibilidad  text        not null default '' check (char_length(disponibilidad) <= 200),
  fuente          text        not null default '' check (char_length(fuente) <= 80),
  autoriza        boolean     not null check (autoriza),
  aviso_version   text        not null default '' check (char_length(aviso_version) <= 40),
  created_at      timestamptz not null default now()
);

create index if not exists talentos_postulaciones_user_idx on public.talentos_postulaciones (user_id, created_at desc);
create index if not exists talentos_postulaciones_conv_idx on public.talentos_postulaciones (convocatoria_id);

-- Antes de guardar: asigna la dueña (la de la convocatoria), fija identificador y fecha desde el servidor
-- y limita la cantidad de registros pendientes por convocatoria para frenar envíos masivos.
create or replace function public.talentos_postulacion_antes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  duena uuid;
  pendientes integer;
begin
  select c.user_id into duena from public.talentos_convocatorias c where c.id = new.convocatoria_id and c.activa;
  if duena is null then
    raise exception 'convocatoria_cerrada' using errcode = 'P0001';
  end if;
  select count(*) into pendientes from public.talentos_postulaciones p where p.convocatoria_id = new.convocatoria_id;
  if pendientes >= 300 then
    raise exception 'limite_alcanzado' using errcode = 'P0001';
  end if;
  new.id := gen_random_uuid();
  new.user_id := duena;
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists talentos_postulacion_antes on public.talentos_postulaciones;
create trigger talentos_postulacion_antes before insert on public.talentos_postulaciones
  for each row execute function public.talentos_postulacion_antes();

alter table public.talentos_postulaciones enable row level security;

drop policy if exists "post_publico_inserta" on public.talentos_postulaciones;
drop policy if exists "post_duena_lee"       on public.talentos_postulaciones;
drop policy if exists "post_duena_borra"     on public.talentos_postulaciones;

create policy "post_publico_inserta" on public.talentos_postulaciones for insert to anon          with check (autoriza);
create policy "post_duena_lee"       on public.talentos_postulaciones for select to authenticated using (auth.uid() = user_id);
create policy "post_duena_borra"     on public.talentos_postulaciones for delete to authenticated using (auth.uid() = user_id);

revoke all on public.talentos_postulaciones from anon, authenticated;
grant insert (convocatoria_id, nombre, celular, zona, experiencia, disponibilidad, fuente, autoriza, aviso_version) on public.talentos_postulaciones to anon;
grant select, delete on public.talentos_postulaciones to authenticated;

revoke all on function public.talentos_postulacion_antes() from public, anon, authenticated;
