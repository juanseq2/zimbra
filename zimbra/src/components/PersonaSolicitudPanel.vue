<script setup lang="ts">
import { onMounted, ref } from 'vue'

interface Solicitud {
  nombre: string
  empresa: string
  correo_electronico: string
  telefono: string | null
  plan_servicio: string
  estado_solicitud: string
  fecha_registro: string
  estado_prospecto: string
  puntaje_interes: number
  vendedor: string | null
}

interface Seguimiento {
  estado: string
  detalle: string
  creado_en: string
}

const props = defineProps<{ apiUrl: string; token: string }>()
const emit = defineEmits<{ cerrarSesion: [] }>()
const solicitud = ref<Solicitud | null>(null)
const historial = ref<Seguimiento[]>([])
const error = ref('')
const cargando = ref(false)

const cargar = async () => {
  cargando.value = true
  error.value = ''
  try {
    const respuesta = await fetch(`${props.apiUrl}/personas-naturales/mi-solicitud`, {
      headers: { Authorization: `Bearer ${props.token}` },
    })
    const datos = await respuesta.json()
    if (!respuesta.ok) throw new Error(datos.error || 'No se pudo consultar la solicitud.')
    solicitud.value = datos.solicitud
    historial.value = datos.historial
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No se pudo cargar el seguimiento.'
  } finally {
    cargando.value = false
  }
}

const formatoFecha = (fecha: string) =>
  new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(fecha))

const etiqueta = (estado: string) =>
  ({
    pendiente: 'Solicitud recibida',
    en_revision: 'En revisión',
    contactada: 'Contacto realizado',
    propuesta_enviada: 'Propuesta enviada',
    pendiente_pago: 'Pendiente de pago',
    activada: 'Servicio activado',
    rechazada: 'Solicitud rechazada',
    archivada: 'Solicitud archivada',
  })[estado] || estado

onMounted(cargar)
</script>

<template>
  <main class="dashboard persona-dashboard">
    <header class="page-header">
      <div>
        <p class="eyebrow">ZIMBRA · SOLICITUD DE SERVICIO</p>
        <h1>Hola, {{ solicitud?.nombre || 'bienvenido' }}</h1>
        <p class="page-description">Consulta el estado y los movimientos de tu solicitud.</p>
      </div>
      <div class="persona-actions">
        <button class="refresh-button" type="button" :disabled="cargando" @click="cargar">
          {{ cargando ? 'Actualizando…' : 'Actualizar' }}
        </button>
        <button class="logout-button" type="button" @click="emit('cerrarSesion')">Cerrar sesión</button>
      </div>
    </header>

    <p v-if="error" class="persona-error" role="alert">{{ error }}</p>
    <p v-if="cargando && !solicitud" class="persona-empty">Cargando solicitud…</p>

    <template v-if="solicitud">
      <section class="persona-card">
        <div class="persona-card-heading">
          <div>
            <p class="eyebrow">ESTADO ACTUAL</p>
            <h2>{{ etiqueta(solicitud.estado_solicitud) }}</h2>
          </div>
          <span class="persona-badge">{{ solicitud.estado_prospecto }}</span>
        </div>
        <p>Tu solicitud está en seguimiento. El estado se actualizará cuando el equipo comercial avance el proceso.</p>
      </section>

      <section class="persona-card">
        <h2>Información de la solicitud</h2>
        <dl class="persona-details">
          <div><dt>Compañía</dt><dd>{{ solicitud.empresa }}</dd></div>
          <div><dt>Servicio solicitado</dt><dd>{{ solicitud.plan_servicio }}</dd></div>
          <div><dt>Correo</dt><dd>{{ solicitud.correo_electronico }}</dd></div>
          <div><dt>Teléfono</dt><dd>{{ solicitud.telefono || 'No registrado' }}</dd></div>
          <div><dt>Fecha de registro</dt><dd>{{ formatoFecha(solicitud.fecha_registro) }}</dd></div>
          <div><dt>Puntaje de interés</dt><dd>{{ solicitud.puntaje_interes }}/100</dd></div>
          <div><dt>Asesor asignado</dt><dd>{{ solicitud.vendedor || 'Pendiente de asignación' }}</dd></div>
        </dl>
      </section>

      <section class="persona-card">
        <h2>Historial del proceso</h2>
        <ol v-if="historial.length" class="persona-timeline">
          <li v-for="(evento, indice) in historial" :key="`${evento.creado_en}-${indice}`">
            <span class="timeline-dot"></span>
            <div>
              <strong>{{ etiqueta(evento.estado) }}</strong>
              <p>{{ evento.detalle }}</p>
              <time>{{ formatoFecha(evento.creado_en) }}</time>
            </div>
          </li>
        </ol>
        <p v-else class="persona-empty">Aún no hay actualizaciones de seguimiento.</p>
      </section>
    </template>
  </main>
</template>

<style scoped>
.persona-actions { display:flex; gap:9px; }
.logout-button { min-height:42px; border:1px solid #dfe4ef; border-radius:9px; padding:0 14px; background:#fff; color:#536078; cursor:pointer; }
.persona-card { margin-bottom:18px; padding:22px; border:1px solid #e8ebf3; border-radius:14px; background:#fff; box-shadow:0 5px 18px rgb(29 44 82 / 4%); }
.persona-card h2 { margin:0 0 12px; font-size:18px; }
.persona-card p { color:#69758b; font-size:14px; line-height:1.55; }
.persona-card-heading { display:flex; align-items:center; justify-content:space-between; gap:16px; }
.persona-card-heading .eyebrow { margin-bottom:7px; }
.persona-card-heading h2 { font-size:23px; }
.persona-badge { border-radius:999px; padding:7px 12px; background:#f0f1ff; color:#4149bb; font-size:12px; font-weight:750; }
.persona-details { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px; margin:0; }
.persona-details div { min-width:0; }
.persona-details dt { color:#8790a3; font-size:12px; }
.persona-details dd { margin:4px 0 0; color:#323c53; font-weight:650; overflow-wrap:anywhere; }
.persona-timeline { display:grid; gap:0; list-style:none; margin:20px 0 0; padding:0; }
.persona-timeline li { position:relative; display:grid; grid-template-columns:18px 1fr; gap:12px; padding-bottom:22px; }
.persona-timeline li:not(:last-child)::before { position:absolute; top:13px; bottom:0; left:6px; width:2px; background:#e4e7f2; content:''; }
.timeline-dot { z-index:1; width:14px; height:14px; margin-top:3px; border:3px solid #dfe1ff; border-radius:50%; background:#555ed3; }
.persona-timeline strong { color:#323c53; font-size:14px; }
.persona-timeline p { margin:4px 0; }
.persona-timeline time { color:#929bad; font-size:11px; }
.persona-error,.persona-empty { color:#7b8498; font-size:14px; }
.persona-error { padding:12px; border:1px solid #f3c7c7; border-radius:9px; color:#9d2929; background:#fff1f0; }
@media(max-width:640px) { .persona-details { grid-template-columns:1fr; } .persona-actions { flex-direction:column; } }
</style>
