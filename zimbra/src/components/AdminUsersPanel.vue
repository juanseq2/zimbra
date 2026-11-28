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

interface SolicitudNatural {
  id_persona: number
  id_cliente_prospecto: number
  nombre: string
  empresa: string
  correo_electronico: string
  telefono: string | null
  plan_servicio: string
  estado_solicitud: string
  activo: number | boolean
  estado_prospecto: string
  puntaje_interes: number
  vendedor: string | null
  fecha_registro: string
}

interface HistorialSolicitud {
  estado: string
  detalle: string
  creado_en: string
  usuario: string | null
}

const props = defineProps<{ apiUrl: string; token: string }>()
const usuarios = ref<Usuario[]>([])
const nuevo = ref({ nombre: '', email: '', password: '', rol: 'vendedor' })
const solicitudes = ref<SolicitudNatural[]>([])
const historiales = ref<Record<number, HistorialSolicitud[]>>({})
const historialAbierto = ref<number | null>(null)
const solicitudNueva = ref({
  nombre: '',
  empresa: '',
  correo_electronico: '',
  password: '',
  telefono: '',
  tipo_identificacion: '',
  numero_identificacion: '',
  plan_servicio: '',
})
const solicitudEditando = ref<number | null>(null)
const cambiosSolicitud = ref({
  nombre: '',
  empresa: '',
  telefono: '',
  plan_servicio: '',
  estado_solicitud: 'pendiente',
  detalle: '',
})
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
    const [listaUsuarios, listaSolicitudes] = await Promise.all([
      solicitar<Usuario[]>('usuarios'),
      solicitar<SolicitudNatural[]>('admin/personas-naturales'),
    ])
    usuarios.value = listaUsuarios
    solicitudes.value = listaSolicitudes
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible cargar usuarios.'
  } finally {
    cargando.value = false
  }
}

const crearSolicitud = async () => {
  error.value = ''
  exito.value = ''
  try {
    await solicitar('admin/personas-naturales', {
      method: 'POST',
      body: JSON.stringify(solicitudNueva.value),
    })
    exito.value = 'Solicitud creada y agregada al embudo de prospectos.'
    solicitudNueva.value = {
      nombre: '',
      empresa: '',
      correo_electronico: '',
      password: '',
      telefono: '',
      tipo_identificacion: '',
      numero_identificacion: '',
      plan_servicio: '',
    }
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible crear la solicitud.'
  }
}

const editarSolicitud = (solicitud: SolicitudNatural) => {
  solicitudEditando.value = solicitud.id_persona
  cambiosSolicitud.value = {
    nombre: solicitud.nombre,
    empresa: solicitud.empresa || '',
    telefono: solicitud.telefono || '',
    plan_servicio: solicitud.plan_servicio,
    estado_solicitud: solicitud.estado_solicitud,
    detalle: '',
  }
}

const verHistorial = async (solicitud: SolicitudNatural) => {
  if (historialAbierto.value === solicitud.id_persona) {
    historialAbierto.value = null
    return
  }
  error.value = ''
  try {
    historiales.value[solicitud.id_persona] = await solicitar<HistorialSolicitud[]>(
      `admin/personas-naturales/${solicitud.id_persona}/historial`,
    )
    historialAbierto.value = solicitud.id_persona
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible consultar el historial.'
  }
}

const guardarSolicitud = async () => {
  if (!solicitudEditando.value) return
  error.value = ''
  exito.value = ''
  try {
    await solicitar(`admin/personas-naturales/${solicitudEditando.value}`, {
      method: 'PATCH',
      body: JSON.stringify(cambiosSolicitud.value),
    })
    exito.value = 'Información y seguimiento actualizados.'
    solicitudEditando.value = null
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible actualizar la solicitud.'
  }
}

const archivarSolicitud = async (solicitud: SolicitudNatural) => {
  const confirmar = window.confirm(`¿Archivar la solicitud de ${solicitud.nombre}?`)
  if (!confirmar) return
  try {
    await solicitar(`admin/personas-naturales/${solicitud.id_persona}`, { method: 'DELETE' })
    exito.value = 'Solicitud archivada; el prospecto comercial se conserva.'
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible archivar la solicitud.'
  }
}

const reactivarSolicitud = async (solicitud: SolicitudNatural) => {
  try {
    await solicitar(`admin/personas-naturales/${solicitud.id_persona}`, {
      method: 'PATCH',
      body: JSON.stringify({ activo: true, estado_solicitud: 'pendiente', detalle: 'Solicitud reactivada por administración.' }),
    })
    exito.value = 'Solicitud reactivada.'
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible reactivar la solicitud.'
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

    <div class="natural-heading">
      <div>
        <h3>Solicitudes de personas naturales</h3>
        <p>Crear, consultar, actualizar el proceso y archivar solicitudes.</p>
      </div>
    </div>

    <form class="natural-create" @submit.prevent="crearSolicitud">
      <label>Nombre<input v-model.trim="solicitudNueva.nombre" maxlength="120" required /></label>
      <label>Compañía<input v-model.trim="solicitudNueva.empresa" maxlength="120" required /></label>
      <label>Correo<input v-model.trim="solicitudNueva.correo_electronico" type="email" maxlength="150" required /></label>
      <label>Contraseña inicial<input v-model="solicitudNueva.password" type="password" minlength="8" maxlength="72" required /></label>
      <label>Teléfono<input v-model.trim="solicitudNueva.telefono" maxlength="30" /></label>
      <label>
        Servicio
        <select v-model="solicitudNueva.plan_servicio" required>
          <option value="">Seleccionar</option>
          <option value="Prueba gratuita 60 días">Prueba gratuita 60 días</option>
          <option value="Plan mensual">Plan mensual</option>
          <option value="Plan empresarial">Plan empresarial</option>
        </select>
      </label>
      <button type="submit">Crear solicitud/prospecto</button>
    </form>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Persona / compañía</th><th>Servicio</th><th>Proceso</th>
            <th>Prospecto</th><th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="solicitud in solicitudes" :key="solicitud.id_persona">
            <tr>
              <td>
                <strong>{{ solicitud.nombre }}</strong><br />
                <small>{{ solicitud.correo_electronico }}</small><br />
                <small>{{ solicitud.empresa || 'Sin compañía' }}</small>
              </td>
              <td>{{ solicitud.plan_servicio }}</td>
              <td>{{ solicitud.estado_solicitud }}<br /><small>{{ solicitud.activo ? 'Cuenta activa' : 'Archivada' }}</small></td>
              <td>
                #{{ solicitud.id_cliente_prospecto }} · {{ solicitud.estado_prospecto || 'sin prospecto' }}<br />
                <small>{{ solicitud.puntaje_interes || 0 }}/100 · {{ solicitud.vendedor || 'sin asesor' }}</small>
              </td>
              <td class="natural-actions">
                <button type="button" class="secondary-button" @click="verHistorial(solicitud)">
                  {{ historialAbierto === solicitud.id_persona ? 'Ocultar proceso' : 'Ver proceso' }}
                </button>
                <button type="button" @click="editarSolicitud(solicitud)">Editar / seguimiento</button>
                <button v-if="solicitud.activo" type="button" class="secondary-button" @click="archivarSolicitud(solicitud)">Archivar</button>
                <button v-else type="button" class="secondary-button" @click="reactivarSolicitud(solicitud)">Reactivar</button>
              </td>
            </tr>
            <tr v-if="historialAbierto === solicitud.id_persona">
              <td colspan="5" class="history-cell">
                <ol v-if="historiales[solicitud.id_persona]?.length" class="admin-timeline">
                  <li v-for="(evento, indice) in historiales[solicitud.id_persona]" :key="`${evento.creado_en}-${indice}`">
                    <strong>{{ evento.estado }}</strong>
                    <span>{{ evento.detalle }}</span>
                    <small>{{ evento.usuario || 'Registro del sistema' }} · {{ evento.creado_en }}</small>
                  </li>
                </ol>
                <p v-else>No hay eventos del proceso.</p>
              </td>
            </tr>
            <tr v-if="solicitudEditando === solicitud.id_persona">
              <td colspan="5">
                <form class="natural-edit" @submit.prevent="guardarSolicitud">
                  <label>Nombre<input v-model.trim="cambiosSolicitud.nombre" maxlength="120" required /></label>
                  <label>Compañía<input v-model.trim="cambiosSolicitud.empresa" maxlength="120" required /></label>
                  <label>Teléfono<input v-model.trim="cambiosSolicitud.telefono" maxlength="30" /></label>
                  <label>Servicio<input v-model.trim="cambiosSolicitud.plan_servicio" maxlength="80" required /></label>
                  <label>
                    Estado del proceso
                    <select v-model="cambiosSolicitud.estado_solicitud">
                      <option value="pendiente">Solicitud recibida</option>
                      <option value="en_revision">En revisión</option>
                      <option value="contactada">Contacto realizado</option>
                      <option value="propuesta_enviada">Propuesta enviada</option>
                      <option value="pendiente_pago">Pendiente de pago</option>
                      <option value="activada">Servicio activado</option>
                      <option value="rechazada">Rechazada</option>
                    </select>
                  </label>
                  <label class="detail-field">Nota de seguimiento<textarea v-model.trim="cambiosSolicitud.detalle" maxlength="500" placeholder="Indica qué ocurrió o cuál es el siguiente paso." /></label>
                  <div class="edit-actions">
                    <button type="submit">Guardar cambios</button>
                    <button type="button" class="secondary-button" @click="solicitudEditando = null">Cancelar</button>
                  </div>
                </form>
              </td>
            </tr>
          </template>
          <tr v-if="!solicitudes.length">
            <td colspan="5" class="empty-state">No hay solicitudes de personas naturales.</td>
          </tr>
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
.natural-heading { padding:20px 22px 14px; border-top:1px solid #edf0f5; }
.natural-heading h3 { margin:0 0 4px; font-size:16px; }
.natural-heading p { margin:0; color:#778198; font-size:12px; }
.natural-create,.natural-edit { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; align-items:end; padding:0 22px 18px; }
.natural-create label,.natural-edit label { display:grid; gap:6px; color:#536078; font-size:12px; font-weight:700; }
.natural-create input,.natural-create select,.natural-edit input,.natural-edit select,.natural-edit textarea { min-width:0; min-height:38px; border:1px solid #dfe4ef; border-radius:8px; padding:8px 10px; font:inherit; }
.natural-create button,.natural-edit button,.natural-actions button { min-height:36px; border:0; border-radius:8px; padding:0 11px; background:#555ed3; color:#fff; font-weight:700; cursor:pointer; }
.natural-actions { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:6px; }
.history-cell { white-space:normal; }
.history-cell p { margin:0; color:#8790a3; }
.admin-timeline { display:grid; gap:12px; margin:0; padding:4px 0 4px 20px; }
.admin-timeline li { display:grid; gap:3px; }
.admin-timeline li strong { color:#323c53; }
.admin-timeline li span { color:#536078; }
.admin-timeline li small { color:#929bad; }
.natural-actions .secondary-button,.natural-edit .secondary-button { border:1px solid #dfe4ef; background:#fff; color:#536078; }
.natural-edit { padding:16px 0 2px; }
.natural-edit textarea { min-height:70px; resize:vertical; }
.detail-field { grid-column:span 2; }
.edit-actions { display:flex; gap:8px; }
@media(max-width:800px){ .admin-create { grid-template-columns:1fr; } }
@media(max-width:900px){ .natural-create,.natural-edit { grid-template-columns:repeat(2,minmax(0,1fr)); } }
@media(max-width:560px){ .natural-create,.natural-edit { grid-template-columns:1fr; } .detail-field { grid-column:auto; } .natural-actions { justify-content:flex-start; } }
</style>
