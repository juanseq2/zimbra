<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

interface Prospecto {
  id_cliente: number
  correo_electronico: string
  nombre: string
  empresa: string | null
  estado_prospecto: string
  puntaje_interes: number
  fecha_registro: string
  fecha_fin_prueba: string
  estado_prueba: 'activa' | 'vencida'
  id_campania: number | null
  nombre_campania: string | null
  id_usuario_asignado: number | null
  vendedor: string | null
  actividades: number
}

interface Vendedor {
  id_usuario: number
  nombre: string
  email: string
  prospectos_activos: number
}

interface Campania {
  id_campania: number
  nombre_campania: string
  canal: string
}

interface Propuesta {
  id_propuesta: number
  id_cliente: number
  nombre_prospecto: string
  id_usuario: number
  vendedor: string
  monto_estimado: number | string
  estado_propuesta: 'borrador' | 'enviada' | 'aceptada' | 'rechazada'
  venta_cerrada: number | boolean
}

interface Actividad {
  id_actividad: number
  url_visitada: string | null
  tipo_evento: string | null
  fecha_actividad: string
}

interface Notificacion {
  id_notificacion: number
  nombre_prospecto: string | null
  mensaje: string
  leida: number | boolean
  creada_en: string
}

interface EventoCrm {
  id_evento: number
  tipo_evento: string
  estado: string
  intentos: number
  ultimo_error: string | null
  creado_en: string
}

interface EstadoCrm {
  configurado: boolean
  webhook: string
  conteos: { estado: string; total: number }[]
  eventos: EventoCrm[]
}

interface Configuracion {
  puntaje_minimo_asignacion: number
  limite_prospectos_vendedor: number
}

const props = defineProps<{ apiUrl: string; token: string }>()
const prospectos = ref<Prospecto[]>([])
const vendedores = ref<Vendedor[]>([])
const campanias = ref<Campania[]>([])
const propuestas = ref<Propuesta[]>([])
const notificaciones = ref<Notificacion[]>([])
const estadoCrm = ref<EstadoCrm | null>(null)
const actividades = ref<Record<number, Actividad[]>>({})
const prospectoActividades = ref<number | null>(null)
const configuracion = ref<Configuracion>({
  puntaje_minimo_asignacion: 50,
  limite_prospectos_vendedor: 30,
})
const cargando = ref(false)
const guardando = ref(false)
const error = ref('')
const exito = ref('')
const prospectoNuevo = ref({ nombre: '', correo_electronico: '', empresa: '', id_campania: '' })
const prospectoParaPropuesta = ref<Prospecto | null>(null)
const nuevaPropuesta = ref({ id_usuario: '', monto_estimado: '' })
const notificacionesSinLeer = computed(
  () => notificaciones.value.filter((item) => !item.leida).length,
)

const api = props.apiUrl.replace(/\/$/, '')

const solicitar = async <T,>(ruta: string, opciones: RequestInit = {}): Promise<T> => {
  const respuesta = await fetch(`${api}/${ruta}`, {
    ...opciones,
    headers: {
      Authorization: `Bearer ${props.token}`,
      ...(opciones.body ? { 'Content-Type': 'application/json' } : {}),
      ...opciones.headers,
    },
  })
  if (!respuesta.headers.get('content-type')?.includes('application/json')) {
    throw new Error(
      `La API respondió sin JSON (${respuesta.status}). Reinicia la API actualizada y revisa la migración MySQL.`,
    )
  }
  const datos: unknown = await respuesta.json()
  if (!respuesta.ok) {
    const mensaje =
      typeof datos === 'object' &&
      datos !== null &&
      'error' in datos &&
      typeof datos.error === 'string'
        ? datos.error
        : `La solicitud falló (${respuesta.status}).`
    throw new Error(mensaje)
  }
  return datos as T
}

const obtenerVisitorId = () => {
  const guardado = sessionStorage.getItem('zimbraVisitorId')
  if (guardado) return guardado
  const id = crypto.randomUUID()
  sessionStorage.setItem('zimbraVisitorId', id)
  return id
}

const cargar = async () => {
  cargando.value = true
  error.value = ''
  try {
    const [leads, sales, campaigns, offers, alerts, crm, settings] = await Promise.all([
      solicitar<Prospecto[]>('prospectos'),
      solicitar<Vendedor[]>('vendedores'),
      solicitar<Campania[]>('campanias'),
      solicitar<Propuesta[]>('propuestas'),
      solicitar<Notificacion[]>('notificaciones'),
      solicitar<EstadoCrm>('crm/sincronizacion'),
      solicitar<Configuracion>('configuracion'),
    ])
    prospectos.value = leads
    vendedores.value = sales
    campanias.value = campaigns
    propuestas.value = offers
    notificaciones.value = alerts
    estadoCrm.value = crm
    configuracion.value = settings
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudieron cargar los datos de prospectos.'
  } finally {
    cargando.value = false
  }
}

const rastrear = async (
  tipo: 'page_view' | 'pagina_precio' | 'solicitud_demo',
  prospectoId?: number,
) => {
  await solicitar('actividad', {
    method: 'POST',
    body: JSON.stringify({
      ...(prospectoId ? { id_cliente: prospectoId } : { visitor_id: obtenerVisitorId() }),
      url_visitada:
        tipo === 'page_view'
          ? window.location.pathname
          : tipo === 'solicitud_demo'
            ? '/demo'
            : '/precios',
      tipo_evento: tipo,
    }),
  })
}

const registrarProspecto = async () => {
  guardando.value = true
  error.value = ''
  exito.value = ''
  try {
    const resultado = await solicitar<{
      id_cliente: number
      puntaje_interes: number
      id_usuario_asignado: number | null
      mensaje: string
    }>('prospectos', {
      method: 'POST',
      body: JSON.stringify({
        ...prospectoNuevo.value,
        visitor_id: obtenerVisitorId(),
      }),
    })
    exito.value = `Prospecto #${resultado.id_cliente} registrado. ${resultado.mensaje}`
    prospectoNuevo.value = { nombre: '', correo_electronico: '', empresa: '', id_campania: '' }
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo registrar el prospecto.'
  } finally {
    guardando.value = false
  }
}

const registrarInteres = async (tipo: 'pagina_precio' | 'solicitud_demo', prospectoId?: number) => {
  error.value = ''
  exito.value = ''
  try {
    await rastrear(tipo, prospectoId)
    exito.value = prospectoId
      ? 'Actividad guardada y puntaje actualizado.'
      : 'Visita guardada. Se asociará al prospecto si se registra desde este navegador.'
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo guardar la actividad.'
  }
}

const asignar = async (prospecto: Prospecto, event: Event) => {
  const idUsuario = Number((event.target as HTMLSelectElement).value)
  if (!idUsuario) return
  error.value = ''
  exito.value = ''
  try {
    await solicitar(`prospectos/${prospecto.id_cliente}/asignacion`, {
      method: 'PATCH',
      body: JSON.stringify({ id_usuario: idUsuario }),
    })
    exito.value = `Prospecto #${prospecto.id_cliente} asignado correctamente.`
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo asignar el prospecto.'
  }
}

const abrirFormularioPropuesta = (prospecto: Prospecto) => {
  prospectoParaPropuesta.value = prospecto
  nuevaPropuesta.value = {
    id_usuario: String(prospecto.id_usuario_asignado || vendedores.value[0]?.id_usuario || ''),
    monto_estimado: '',
  }
}

const crearPropuesta = async () => {
  if (!prospectoParaPropuesta.value) return
  error.value = ''
  exito.value = ''
  try {
    const resultado = await solicitar<{ id_propuesta: number }>('propuestas', {
      method: 'POST',
      body: JSON.stringify({
        id_cliente: prospectoParaPropuesta.value.id_cliente,
        id_usuario: Number(nuevaPropuesta.value.id_usuario),
        monto_estimado: Number(nuevaPropuesta.value.monto_estimado),
      }),
    })
    exito.value = `Propuesta #${resultado.id_propuesta} creada en borrador.`
    prospectoParaPropuesta.value = null
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo crear la propuesta.'
  }
}

const cambiarEstadoPropuesta = async (propuesta: Propuesta, event: Event) => {
  const estado = (event.target as HTMLSelectElement).value
  error.value = ''
  exito.value = ''
  try {
    await solicitar(`propuestas/${propuesta.id_propuesta}/estado`, {
      method: 'PATCH',
      body: JSON.stringify({ estado_propuesta: estado }),
    })
    exito.value = `Estado de la propuesta #${propuesta.id_propuesta} actualizado.`
    await cargar()
  } catch (e) {
    const mensajeError = e instanceof Error ? e.message : 'No se pudo actualizar la propuesta.'
    await cargar()
    error.value = mensajeError
  }
}

const marcarLeida = async (notificacion: Notificacion) => {
  try {
    await solicitar(`notificaciones/${notificacion.id_notificacion}/leida`, { method: 'PATCH' })
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo actualizar la notificación.'
  }
}

const reintentarCrm = async (evento: EventoCrm) => {
  error.value = ''
  exito.value = ''
  try {
    await solicitar(`crm/sincronizacion/${evento.id_evento}/reintentar`, { method: 'POST' })
    exito.value = `El evento CRM #${evento.id_evento} quedó en cola para reintento.`
    await cargar()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo reintentar el evento CRM.'
  }
}

const verActividades = async (idCliente: number) => {
  if (prospectoActividades.value === idCliente) {
    prospectoActividades.value = null
    return
  }
  error.value = ''
  try {
    actividades.value[idCliente] = await solicitar<Actividad[]>(
      `prospectos/${idCliente}/actividades`,
    )
    prospectoActividades.value = idCliente
  } catch (e) {
    error.value =
      e instanceof Error ? e.message : 'No se pudo consultar la actividad del prospecto.'
  }
}

const fecha = (valor: string) =>
  new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(new Date(valor))

const moneda = (valor: number | string) =>
  new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'USD' }).format(Number(valor) || 0)

onMounted(async () => {
  try {
    await rastrear('page_view')
  } catch (e) {
    error.value =
      e instanceof Error
        ? `No se pudo registrar la visita: ${e.message}`
        : 'No se pudo registrar la visita.'
  }
  await cargar()
})
</script>

<template>
  <section class="prospectos-panel">
    <header class="prospectos-heading">
      <div>
        <p class="prospectos-eyebrow">GESTIÓN COMERCIAL</p>
        <h2>Prospectos y seguimiento</h2>
        <p>Registro de pruebas de 60 días, actividad, calificación, vendedores y propuestas.</p>
      </div>
      <button class="prospectos-refresh" type="button" :disabled="cargando" @click="cargar">
        {{ cargando ? 'Actualizando…' : 'Actualizar' }}
      </button>
    </header>

    <p v-if="error" class="prospectos-message prospects-error" role="alert">{{ error }}</p>
    <p v-if="exito" class="prospectos-message prospects-success" role="status">{{ exito }}</p>

    <section class="prospectos-card">
      <h3>Registrar prospecto</h3>
      <p class="prospectos-hint">
        Se inicia la prueba gratuita por 60 días y se vincula la navegación anónima de este
        navegador.
      </p>
      <form class="prospectos-form" @submit.prevent="registrarProspecto">
        <label>
          Nombre
          <input
            v-model.trim="prospectoNuevo.nombre"
            required
            maxlength="120"
            autocomplete="name"
          />
        </label>
        <label>
          Correo
          <input
            v-model.trim="prospectoNuevo.correo_electronico"
            type="email"
            required
            maxlength="150"
            autocomplete="email"
          />
        </label>
        <label>
          Empresa
          <input
            v-model.trim="prospectoNuevo.empresa"
            maxlength="120"
            autocomplete="organization"
          />
        </label>
        <label>
          Campaña
          <select v-model="prospectoNuevo.id_campania">
            <option value="">Sin campaña</option>
            <option
              v-for="campania in campanias"
              :key="campania.id_campania"
              :value="String(campania.id_campania)"
            >
              {{ campania.nombre_campania }} · {{ campania.canal }}
            </option>
          </select>
        </label>
        <button class="prospectos-primary" type="submit" :disabled="guardando">
          {{ guardando ? 'Registrando…' : 'Iniciar prueba gratis' }}
        </button>
      </form>
      <div class="prospectos-actions">
        <button type="button" @click="registrarInteres('pagina_precio')">
          Simular visita a precios
        </button>
        <button type="button" @click="registrarInteres('solicitud_demo')">
          Simular solicitud de demo
        </button>
        <span
          >La asignación automática comienza en
          {{ configuracion.puntaje_minimo_asignacion }} puntos.</span
        >
      </div>
    </section>

    <section class="prospectos-card">
      <div class="prospectos-title-row">
        <div>
          <h3>Prospectos registrados</h3>
          <p class="prospectos-hint">
            La asignación automática respeta un máximo de
            {{ configuracion.limite_prospectos_vendedor }} prospectos activos por vendedor.
          </p>
        </div>
        <span class="prospectos-count">{{ prospectos.length }}</span>
      </div>
      <div class="prospectos-table-wrap">
        <table class="prospectos-table">
          <thead>
            <tr>
              <th>Prospecto</th>
              <th>Estado / prueba</th>
              <th>Interés</th>
              <th>Actividad</th>
              <th>Vendedor</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="prospecto in prospectos" :key="prospecto.id_cliente">
              <tr>
                <td>
                  <strong>{{ prospecto.nombre }}</strong>
                  <small>{{ prospecto.correo_electronico }}</small>
                  <small
                    >{{ prospecto.empresa || 'Sin empresa' }} ·
                    {{ prospecto.nombre_campania || 'Sin campaña' }}</small
                  >
                </td>
                <td>
                  <span class="prospectos-status">{{ prospecto.estado_prospecto }}</span>
                  <small :class="prospecto.estado_prueba === 'vencida' ? 'trial-expired' : ''">
                    Prueba {{ prospecto.estado_prueba }} · vence
                    {{ fecha(prospecto.fecha_fin_prueba) }}
                  </small>
                </td>
                <td>
                  <strong>{{ prospecto.puntaje_interes }}/100</strong>
                </td>
                <td>{{ prospecto.actividades }}</td>
                <td>
                  <select
                    :value="prospecto.id_usuario_asignado || ''"
                    aria-label="Asignar vendedor"
                    @change="asignar(prospecto, $event)"
                  >
                    <option value="" disabled>Sin asignar</option>
                    <option
                      v-for="vendedor in vendedores"
                      :key="vendedor.id_usuario"
                      :value="vendedor.id_usuario"
                      :disabled="
                        vendedor.prospectos_activos >= configuracion.limite_prospectos_vendedor &&
                        vendedor.id_usuario !== prospecto.id_usuario_asignado
                      "
                    >
                      {{ vendedor.nombre }} ({{ vendedor.prospectos_activos }}/{{
                        configuracion.limite_prospectos_vendedor
                      }})
                    </option>
                  </select>
                </td>
                <td class="prospectos-row-actions">
                  <button type="button" @click="verActividades(prospecto.id_cliente)">
                    Historial
                  </button>
                  <button
                    type="button"
                    @click="registrarInteres('pagina_precio', prospecto.id_cliente)"
                  >
                    Precio
                  </button>
                  <button
                    type="button"
                    @click="registrarInteres('solicitud_demo', prospecto.id_cliente)"
                  >
                    Demo
                  </button>
                  <button
                    type="button"
                    :disabled="!vendedores.length"
                    @click="abrirFormularioPropuesta(prospecto)"
                  >
                    Propuesta
                  </button>
                </td>
              </tr>
              <tr v-if="prospectoActividades === prospecto.id_cliente">
                <td colspan="6" class="activity-details">
                  <ul>
                    <li
                      v-for="actividad in actividades[prospecto.id_cliente]"
                      :key="actividad.id_actividad"
                    >
                      <strong>{{ actividad.tipo_evento || 'actividad' }}</strong>
                      <span>
                        {{ actividad.url_visitada || '—' }} ·
                        {{ fecha(actividad.fecha_actividad) }}
                      </span>
                    </li>
                    <li v-if="!actividades[prospecto.id_cliente]?.length">
                      No hay actividad registrada.
                    </li>
                  </ul>
                </td>
              </tr>
            </template>
            <tr v-if="!prospectos.length">
              <td colspan="6" class="prospectos-empty">
                {{ cargando ? 'Cargando prospectos…' : 'Todavía no hay prospectos registrados.' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!vendedores.length" class="prospectos-hint prospects-warning">
        No hay vendedores activos. Registra usuarios con rol <code>vendedor</code> en MySQL para
        habilitar la asignación.
      </p>

      <form v-if="prospectoParaPropuesta" class="proposal-form" @submit.prevent="crearPropuesta">
        <h4>Nueva propuesta para {{ prospectoParaPropuesta.nombre }}</h4>
        <label>
          Vendedor
          <select v-model="nuevaPropuesta.id_usuario" required>
            <option
              v-for="vendedor in vendedores"
              :key="vendedor.id_usuario"
              :value="String(vendedor.id_usuario)"
            >
              {{ vendedor.nombre }}
            </option>
          </select>
        </label>
        <label>
          Monto estimado (USD)
          <input
            v-model="nuevaPropuesta.monto_estimado"
            type="number"
            min="0.01"
            step="0.01"
            required
          />
        </label>
        <button class="prospectos-primary" type="submit">Guardar borrador</button>
        <button type="button" @click="prospectoParaPropuesta = null">Cancelar</button>
      </form>
    </section>

    <section class="prospectos-card">
      <h3>Propuestas y avance de venta</h3>
      <div class="prospectos-table-wrap">
        <table class="prospectos-table">
          <thead>
            <tr>
              <th>Propuesta</th>
              <th>Prospecto</th>
              <th>Vendedor</th>
              <th>Monto</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="propuesta in propuestas" :key="propuesta.id_propuesta">
              <td>#{{ propuesta.id_propuesta }}</td>
              <td>{{ propuesta.nombre_prospecto }}</td>
              <td>{{ propuesta.vendedor }}</td>
              <td>{{ moneda(propuesta.monto_estimado) }}</td>
              <td>
                <select
                  :value="propuesta.estado_propuesta"
                  :disabled="Boolean(propuesta.venta_cerrada)"
                  aria-label="Estado de propuesta"
                  @change="cambiarEstadoPropuesta(propuesta, $event)"
                >
                  <option value="borrador">Borrador</option>
                  <option value="enviada">Enviada</option>
                  <option value="aceptada">Aceptada</option>
                  <option value="rechazada">Rechazada</option>
                </select>
                <small v-if="propuesta.venta_cerrada">Venta cerrada</small>
              </td>
            </tr>
            <tr v-if="!propuestas.length">
              <td colspan="5" class="prospectos-empty">No hay propuestas creadas.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="prospectos-card">
      <div class="prospectos-title-row">
        <div>
          <h3>Sincronización CRM</h3>
          <p class="prospectos-hint">
            {{
              estadoCrm?.configurado
                ? 'Webhook configurado; los eventos se envían en segundo plano.'
                : 'Webhook sin configurar; los cierres quedan en cola y no se reportan como sincronizados.'
            }}
          </p>
        </div>
        <span class="prospectos-count">{{ estadoCrm?.eventos.length || 0 }}</span>
      </div>
      <ul v-if="estadoCrm?.eventos.length" class="notifications-list">
        <li v-for="evento in estadoCrm.eventos" :key="evento.id_evento">
          <div>
            <strong>Evento #{{ evento.id_evento }} · {{ evento.tipo_evento }}</strong>
            <p>Estado: {{ evento.estado }} · intentos: {{ evento.intentos }}</p>
            <small v-if="evento.ultimo_error">{{ evento.ultimo_error }}</small>
          </div>
          <button v-if="evento.estado === 'error'" type="button" @click="reintentarCrm(evento)">
            Reintentar
          </button>
        </li>
      </ul>
      <p v-else class="prospectos-empty">No hay eventos de venta para sincronizar.</p>
    </section>

    <section class="prospectos-card">
      <div class="prospectos-title-row">
        <div>
          <h3>Notificaciones de asignación</h3>
          <p class="prospectos-hint">Avisos internos para el vendedor asignado.</p>
        </div>
        <span class="prospectos-count">{{ notificacionesSinLeer }}</span>
      </div>
      <ul v-if="notificaciones.length" class="notifications-list">
        <li
          v-for="notificacion in notificaciones"
          :key="notificacion.id_notificacion"
          :class="{ unread: !notificacion.leida }"
        >
          <div>
            <strong>{{ notificacion.nombre_prospecto || 'Prospecto' }}</strong>
            <p>{{ notificacion.mensaje }}</p>
            <small>{{ fecha(notificacion.creada_en) }}</small>
          </div>
          <button v-if="!notificacion.leida" type="button" @click="marcarLeida(notificacion)">
            Marcar leída
          </button>
        </li>
      </ul>
      <p v-else class="prospectos-empty">No hay notificaciones.</p>
    </section>
  </section>
</template>

<style scoped>
.prospectos-panel {
  display: grid;
  gap: 18px;
}

.prospectos-heading,
.prospectos-title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.prospectos-heading {
  padding: 5px 2px 0;
}

.prospectos-heading h2,
.prospectos-card h3 {
  margin: 0 0 5px;
  color: #172033;
  font-size: 18px;
}

.prospectos-heading > div > p:last-child,
.prospectos-hint {
  margin: 0;
  color: #778198;
  font-size: 12px;
}

.prospectos-eyebrow {
  margin: 0 0 6px;
  color: #5865d8;
  font-size: 10px;
  font-weight: 800;
  letter-spacing: 0.13em;
}

.prospectos-card {
  min-width: 0;
  overflow: hidden;
  padding: 19px 21px;
  border: 1px solid #e8ebf3;
  border-radius: 14px;
  background: #fff;
  box-shadow: 0 5px 18px rgb(29 44 82 / 4%);
}

.prospectos-form {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  align-items: end;
  gap: 12px;
  margin-top: 16px;
}

.prospectos-form label,
.proposal-form label {
  display: grid;
  gap: 6px;
  color: #536078;
  font-size: 12px;
  font-weight: 650;
}

.prospectos-panel input,
.prospectos-panel select {
  min-width: 0;
  height: 38px;
  padding: 0 10px;
  border: 1px solid #dfe3ed;
  border-radius: 8px;
  color: #333d53;
  background: #fff;
  font: inherit;
  font-size: 12px;
}

.prospectos-panel input:focus,
.prospectos-panel select:focus {
  border-color: #737be0;
  outline: 3px solid rgb(115 123 224 / 13%);
}

.prospectos-primary,
.prospectos-refresh,
.prospectos-row-actions button,
.prospectos-actions button,
.proposal-form > button:not(.prospectos-primary),
.notifications-list button {
  min-height: 36px;
  padding: 0 12px;
  border: 0;
  border-radius: 8px;
  color: #fff;
  background: #555ed3;
  font: inherit;
  font-size: 11px;
  font-weight: 700;
  cursor: pointer;
}

.prospectos-refresh {
  flex: 0 0 auto;
}

.prospectos-panel button:disabled {
  cursor: not-allowed;
  opacity: 0.58;
}

.prospectos-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 9px;
  margin-top: 13px;
}

.prospectos-actions button,
.prospectos-row-actions button,
.proposal-form > button:not(.prospectos-primary),
.notifications-list button {
  min-height: 30px;
  color: #4d57c2;
  background: #f0f1ff;
}

.prospectos-actions span {
  color: #778198;
  font-size: 11px;
}

.prospectos-message {
  margin: 0;
  padding: 11px 14px;
  border: 1px solid;
  border-radius: 9px;
  font-size: 13px;
}

.prospects-error {
  border-color: #f3c7c7;
  color: #9d2929;
  background: #fff1f0;
}

.prospects-success {
  border-color: #bce6d0;
  color: #176844;
  background: #edfbf3;
}

.prospects-warning {
  margin-top: 12px;
  color: #8d5d10;
}

.prospectos-count {
  display: inline-grid;
  min-width: 29px;
  height: 27px;
  place-items: center;
  padding: 0 7px;
  border-radius: 20px;
  color: #535dc9;
  background: #f0f1ff;
  font-size: 12px;
  font-weight: 750;
}

.prospectos-table-wrap {
  margin: 15px -21px -19px;
  overflow-x: auto;
  border-top: 1px solid #edf0f5;
}

.prospectos-table {
  width: 100%;
  border-collapse: collapse;
  text-align: left;
  white-space: nowrap;
}

.prospectos-table th,
.prospectos-table td {
  padding: 11px 15px;
  border-bottom: 1px solid #edf0f5;
  color: #4a556b;
  font-size: 12px;
  vertical-align: middle;
}

.prospectos-table th {
  color: #788198;
  background: #fafbfe;
  font-size: 10px;
  font-weight: 750;
}

.prospectos-table td:first-child {
  min-width: 230px;
}

.prospectos-table td > strong,
.prospectos-table small {
  display: block;
}

.prospectos-table small {
  margin-top: 4px;
  color: #8790a3;
  font-size: 10px;
}

.prospectos-table .trial-expired {
  color: #ad3131;
}

.prospectos-status {
  display: inline-block;
  padding: 4px 7px;
  border-radius: 20px;
  color: #366e58;
  background: #eaf8f0;
  font-size: 10px;
  font-weight: 700;
  text-transform: capitalize;
}

.prospectos-row-actions {
  display: flex;
  gap: 5px;
}

.prospectos-empty {
  padding: 18px !important;
  color: #8790a3 !important;
  text-align: center;
}

.activity-details {
  white-space: normal;
  background: #fafbff;
}

.activity-details ul {
  display: grid;
  gap: 7px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.activity-details li {
  display: flex;
  flex-wrap: wrap;
  gap: 5px 12px;
  color: #536078;
  font-size: 11px;
}

.proposal-form {
  display: flex;
  align-items: end;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 18px;
  padding: 14px;
  border: 1px solid #e9ebf5;
  border-radius: 10px;
  background: #fafbff;
}

.proposal-form h4 {
  width: 100%;
  margin: 0;
  font-size: 13px;
}

.proposal-form label {
  min-width: 180px;
}

.notifications-list {
  display: grid;
  gap: 0;
  margin: 14px 0 0;
  padding: 0;
  list-style: none;
}

.notifications-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-top: 1px solid #edf0f5;
}

.notifications-list li.unread {
  border-left: 3px solid #555ed3;
  padding-left: 10px;
}

.notifications-list p {
  margin: 4px 0;
  color: #536078;
  font-size: 12px;
}

.notifications-list small {
  color: #8790a3;
  font-size: 10px;
}

@media (max-width: 760px) {
  .prospectos-form {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 520px) {
  .prospectos-card {
    padding: 15px;
  }

  .prospectos-form {
    grid-template-columns: 1fr;
  }

  .prospectos-table-wrap {
    margin-right: -15px;
    margin-left: -15px;
  }

  .prospectos-heading {
    align-items: flex-start;
  }
}
</style>
