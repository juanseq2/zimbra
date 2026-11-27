<script setup lang="ts">
import { onMounted, ref } from 'vue'

interface Usuario {
  id_usuario: number
  nombre: string
  email: string
  rol: 'administrador' | 'vendedor' | 'invitado'
  activo: number | boolean
  ultimo_acceso: string | null
  fecha_creacion: string
}

const props = defineProps<{ apiUrl: string; token: string }>()
const usuarios = ref<Usuario[]>([])
const nuevo = ref({ nombre: '', email: '', password: '', rol: 'vendedor' })
const error = ref('')
const exito = ref('')
const cargando = ref(false)

const solicitar = async <T,>(ruta: string, opciones: RequestInit = {}) => {
  const respuesta = await fetch(`${props.apiUrl}/${ruta}`, {
    ...opciones,
    headers: {
      Authorization: `Bearer ${props.token}`,
      ...(opciones.body ? { 'Content-Type': 'application/json' } : {}),
      ...opciones.headers,
    },
  })
  const datos = await respuesta.json()
  if (!respuesta.ok) throw new Error(datos.error || 'La solicitud falló.')
  return datos as T
}

const cargar = async () => {
  cargando.value = true
  error.value = ''
  try {
    usuarios.value = await solicitar<Usuario[]>('usuarios')
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible cargar usuarios.'
  } finally {
    cargando.value = false
  }
}

const crear = async () => {
  error.value = ''
  exito.value = ''
  try {
    await solicitar('usuarios', {
      method: 'POST',
      body: JSON.stringify(nuevo.value),
    })
    exito.value = 'Usuario creado correctamente.'
    nuevo.value = { nombre: '', email: '', password: '', rol: 'vendedor' }
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible crear el usuario.'
  }
}

const cambiarEstado = async (usuario: Usuario) => {
  try {
    await solicitar(`usuarios/${usuario.id_usuario}`, {
      method: 'PATCH',
      body: JSON.stringify({ activo: !usuario.activo }),
    })
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible actualizar el usuario.'
  }
}

onMounted(cargar)
</script>

<template>
  <section class="admin-users panel">
    <div class="section-heading">
      <span class="section-number">ADM</span>
      <div>
        <h2>Administración de usuarios</h2>
        <p>Crea cuentas con rol administrador, vendedor o invitado.</p>
      </div>
    </div>

    <p v-if="error" class="admin-message admin-error">{{ error }}</p>
    <p v-if="exito" class="admin-message admin-success">{{ exito }}</p>

    <form class="admin-create" @submit.prevent="crear">
      <label>Nombre<input v-model.trim="nuevo.nombre" maxlength="100" required /></label>
      <label>Correo<input v-model.trim="nuevo.email" type="email" maxlength="150" required /></label>
      <label>Contraseña<input v-model="nuevo.password" type="password" minlength="8" maxlength="72" required /></label>
      <label>
        Rol
        <select v-model="nuevo.rol">
          <option value="administrador">Administrador</option>
          <option value="vendedor">Vendedor</option>
          <option value="invitado">Invitado</option>
        </select>
      </label>
      <button type="submit">Crear usuario</button>
    </form>

    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Usuario</th><th>Rol</th><th>Estado</th><th>Acción</th></tr>
        </thead>
        <tbody>
          <tr v-for="usuario in usuarios" :key="usuario.id_usuario">
            <td><strong>{{ usuario.nombre }}</strong><br /><small>{{ usuario.email }}</small></td>
            <td>{{ usuario.rol }}</td>
            <td>{{ usuario.activo ? 'Activo' : 'Inactivo' }}</td>
            <td><button type="button" @click="cambiarEstado(usuario)">{{ usuario.activo ? 'Desactivar' : 'Activar' }}</button></td>
          </tr>
          <tr v-if="!usuarios.length"><td colspan="4" class="empty-state">{{ cargando ? 'Cargando…' : 'No hay usuarios.' }}</td></tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.admin-create { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)) auto; gap:10px; align-items:end; padding:0 22px 18px; }
.admin-create label { display:grid; gap:6px; color:#536078; font-size:12px; font-weight:700; }
.admin-create input,.admin-create select { height:38px; border:1px solid #dfe4ef; border-radius:8px; padding:0 10px; }
.admin-create button,.table-wrap button { min-height:38px; border:0; border-radius:8px; background:#555ed3; color:#fff; font-weight:700; cursor:pointer; }
.admin-message { margin:0 22px 14px; padding:10px 12px; border-radius:8px; font-size:13px; }
.admin-error { background:#fff1f0; color:#9d2929; }
.admin-success { background:#edfbf3; color:#176844; }
.table-wrap button { min-height:32px; padding:0 10px; }
@media(max-width:800px){ .admin-create { grid-template-columns:1fr; } }
</style>
