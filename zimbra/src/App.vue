<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import ProspectosPanel from './components/ProspectosPanel.vue'
import AuthPage from './components/AuthPage.vue'
import AdminUsersPanel from './components/AdminUsersPanel.vue'

interface UsuarioSesion {
  id: number
  nombre: string
  correo: string
  rol: string
}

interface Venta {
  id_venta: number
  fecha_cierre: string
  monto_final: number | string
}

interface Campania {
  id_campania: number
  nombre_campania: string
  total_prospectos: number
  total_ventas: number
  tasa_conversion_pct: number | string
}

interface ReporteMensual {
  [columna: string]: string | number | null
}

interface Propuesta {
  id_propuesta: number
  id_cliente: number
  id_usuario: number
  monto_estimado: number | string
}

interface Mensaje {
  tipo: 'error' | 'exito'
  texto: string
}

const apiUrl = (import.meta.env.VITE_API_URL || 'http://localhost:3000/api').replace(/\/$/, '')
const token = ref('')
const usuario = ref<UsuarioSesion | null>(null)

const ventas = ref<Venta[]>([])
const tasaConversion = ref<Campania[]>([])
const reporteMensual = ref<ReporteMensual[]>([])
const propuestasPendientes = ref<Propuesta[]>([])
const mensaje = ref<Mensaje | null>(null)
const cargando = ref(false)
const propuestaEnProceso = ref<number | null>(null)

const cerrarSesion = () => {
  token.value = ''
  usuario.value = null
  localStorage.removeItem('zimbraSesion')
}

const iniciarSesion = (sesion: { token: string; usuario: UsuarioSesion }) => {
  token.value = sesion.token
  usuario.value = sesion.usuario
  localStorage.setItem('zimbraSesion', JSON.stringify(sesion))
}

const nombresColumnasReporte: Record<string, string> = {
  vendedor: 'Vendedor',
  cantidad_ventas: 'Ventas',
  ingreso_total: 'Ingreso total',
}

const obtenerDatos = async <T,>(recurso: string): Promise<T> => {
  const respuesta = await fetch(`${apiUrl}/${recurso}`, {
    headers: { Authorization: `Bearer ${token.value}` },
  })
  if (!respuesta.headers.get('content-type')?.includes('application/json')) {
    throw new Error(
      `La API respondió sin JSON (${respuesta.status}). Revisa la versión del servidor.`,
    )
  }
  const datos = await respuesta.json()

  if (!respuesta.ok) {
    throw new Error(datos.error || `No se pudieron cargar los datos (${respuesta.status}).`)
  }

  return datos
}

const cargarDatos = async (limpiarMensaje = true) => {
  cargando.value = true
  if (limpiarMensaje) mensaje.value = null

  try {
    const [nuevasVentas, nuevaTasa, nuevoReporte, nuevasPropuestas] = await Promise.all([
      obtenerDatos<Venta[]>('ventas'),
      obtenerDatos<Campania[]>('tasa-conversion'),
      obtenerDatos<ReporteMensual[]>('reporte-mensual'),
      obtenerDatos<Propuesta[]>('propuestas-pendientes'),
    ])

    ventas.value = nuevasVentas
    tasaConversion.value = nuevaTasa
    reporteMensual.value = nuevoReporte
    propuestasPendientes.value = nuevasPropuestas
  } catch (error) {
    mensaje.value = {
      tipo: 'error',
      texto: `No fue posible cargar el panel. ${error instanceof Error ? error.message : 'Revisa que la API esté activa.'}`,
    }
  } finally {
    cargando.value = false
  }
}

const cerrarVenta = async (propuesta: Propuesta) => {
  propuestaEnProceso.value = propuesta.id_propuesta
  mensaje.value = null

  try {
    const respuesta = await fetch(`${apiUrl}/cerrar-venta`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token.value}`,
      },
      body: JSON.stringify({
        id_propuesta: propuesta.id_propuesta,
        id_usuario: propuesta.id_usuario,
        monto_final: propuesta.monto_estimado,
        metodo_pago: 'Transferencia Bancaria',
      }),
    })
    if (!respuesta.headers.get('content-type')?.includes('application/json')) {
      throw new Error(
        `La API respondió sin JSON (${respuesta.status}). Revisa la versión del servidor.`,
      )
    }
    const datos = await respuesta.json()

    if (!respuesta.ok) {
      throw new Error(datos.error || `No se pudo cerrar la venta (${respuesta.status}).`)
    }

    mensaje.value = {
      tipo: 'exito',
      texto: `Venta #${datos.venta_creada_id} cerrada; factura ${datos.numero_factura || `#${datos.id_factura}`} emitida. ${
        datos.sincronizacion_crm === 'sin_configurar'
          ? 'La sincronización CRM queda pendiente de configurar.'
          : 'La sincronización CRM se procesará en segundo plano.'
      }`,
    }
    await cargarDatos(false)
  } catch (error) {
    mensaje.value = {
      tipo: 'error',
      texto: error instanceof Error ? error.message : 'Ocurrió un error al cerrar la venta.',
    }
  } finally {
    propuestaEnProceso.value = null
  }
}

const formatearMoneda = (monto: number | string | null | undefined) =>
  new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'USD' }).format(Number(monto) || 0)

const formatearFecha = (fecha: string | Date | null | undefined) => {
  if (!fecha) return '—'

  return new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(new Date(fecha))
}

const formatearColumna = (columna: string) =>
  nombresColumnasReporte[columna] ||
  columna.replaceAll('_', ' ').replace(/\b\w/g, (letra: string) => letra.toUpperCase())

const columnasReporte = computed(() => Object.keys(reporteMensual.value[0] || {}))
const ingresoMaximo = computed(() =>
  Math.max(0, ...reporteMensual.value.map((fila) => Number(fila.ingreso_total) || 0)),
)
const conversionMaxima = computed(() =>
  Math.max(0, ...tasaConversion.value.map((campania) => Number(campania.tasa_conversion_pct) || 0)),
)

const anchoBarraIngreso = (ingreso: string | number | null | undefined) =>
  ingresoMaximo.value > 0
    ? Math.max(0, Math.min(100, ((Number(ingreso) || 0) / ingresoMaximo.value) * 100))
    : 0

const anchoBarraConversion = (conversion: string | number) =>
  conversionMaxima.value > 0
    ? Math.max(0, Math.min(100, ((Number(conversion) || 0) / conversionMaxima.value) * 100))
    : 0

onMounted(() => {
  const guardada = localStorage.getItem('zimbraSesion')
  if (guardada) {
    try {
      const sesion = JSON.parse(guardada) as { token: string; usuario: UsuarioSesion }
      if (sesion.token && sesion.usuario) iniciarSesion(sesion)
    } catch {
      localStorage.removeItem('zimbraSesion')
    }
  }
  if (token.value) cargarDatos()
})
</script>

<template>
  <AuthPage v-if="!usuario" :api-url="apiUrl" @autenticado="iniciarSesion" />

  <main v-else-if="usuario.rol === 'persona_natural'" class="dashboard persona-shell">
    <header class="page-header">
      <div>
        <p class="eyebrow">ZIMBRA · CUENTA PERSONAL</p>
        <h1>Solicitud de servicio</h1>
        <p class="page-description">Hola, {{ usuario.nombre }}. Tu solicitud fue registrada.</p>
      </div>
      <button class="refresh-button" type="button" @click="cerrarSesion">Cerrar sesión</button>
    </header>
    <section class="panel persona-status">
      <h2>Tu cuenta está creada</h2>
      <p>Un asesor comercial podrá revisar tu solicitud y ponerse en contacto contigo.</p>
      <p><strong>Correo:</strong> {{ usuario.correo }}</p>
    </section>
  </main>

  <main v-else class="dashboard">
    <header class="page-header">
      <div>
        <p class="eyebrow">ZIMBRA · VENTAS</p>
        <h1>Panel de consultas</h1>
        <p class="page-description">Resumen de propuestas, ventas y campañas.</p>
      </div>
      <div class="header-actions">
        <span class="session-user">{{ usuario?.nombre }} · {{ usuario?.rol }}</span>
        <button class="refresh-button" type="button" :disabled="cargando" @click="cargarDatos()">
          <span aria-hidden="true">{{ cargando ? '…' : '↻' }}</span>
          {{ cargando ? 'Actualizando' : 'Actualizar' }}
        </button>
        <button class="logout-button" type="button" @click="cerrarSesion">Salir</button>
      </div>
    </header>

    <div
      v-if="mensaje"
      class="notice"
      :class="`notice--${mensaje.tipo}`"
      role="status"
      aria-live="polite"
    >
      {{ mensaje.texto }}
    </div>

    <div v-if="cargando && !ventas.length && !tasaConversion.length" class="loading" role="status">
      Cargando información del panel…
    </div>

    <div class="sections">
      <AdminUsersPanel v-if="usuario?.rol === 'administrador'" :api-url="apiUrl" :token="token" />
      <ProspectosPanel :api-url="apiUrl" :token="token" />

      <section class="panel">
        <div class="section-heading">
          <span class="section-number">01</span>
          <div>
            <h2>Propuestas pendientes de venta</h2>
            <p>Propuestas aceptadas que aún no se han convertido en venta.</p>
          </div>
          <span class="count-badge">{{ propuestasPendientes.length }}</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID propuesta</th>
                <th>ID cliente</th>
                <th>Monto estimado</th>
                <th class="action-column">Acción</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="propuesta in propuestasPendientes" :key="propuesta.id_propuesta">
                <td class="id-cell">#{{ propuesta.id_propuesta }}</td>
                <td>#{{ propuesta.id_cliente }}</td>
                <td>{{ formatearMoneda(propuesta.monto_estimado) }}</td>
                <td class="action-column">
                  <button
                    class="table-button"
                    type="button"
                    :disabled="propuestaEnProceso !== null"
                    @click="cerrarVenta(propuesta)"
                  >
                    {{
                      propuestaEnProceso === propuesta.id_propuesta ? 'Procesando…' : 'Cerrar venta'
                    }}
                  </button>
                </td>
              </tr>
              <tr v-if="!propuestasPendientes.length">
                <td class="empty-state" colspan="4">
                  {{
                    cargando ? 'Cargando propuestas…' : 'No hay propuestas aceptadas pendientes.'
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="panel">
        <div class="section-heading">
          <span class="section-number">02</span>
          <div>
            <h2>Ventas registradas</h2>
            <p>Historial de ventas cerradas.</p>
          </div>
          <span class="count-badge">{{ ventas.length }}</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID venta</th>
                <th>Fecha de cierre</th>
                <th>Monto final</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="venta in ventas" :key="venta.id_venta">
                <td class="id-cell">#{{ venta.id_venta }}</td>
                <td>{{ formatearFecha(venta.fecha_cierre) }}</td>
                <td class="amount-cell">{{ formatearMoneda(venta.monto_final) }}</td>
              </tr>
              <tr v-if="!ventas.length">
                <td class="empty-state" colspan="3">
                  {{ cargando ? 'Cargando ventas…' : 'Todavía no hay ventas registradas.' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="panel">
        <div class="section-heading">
          <span class="section-number">03</span>
          <div>
            <h2>Tasa de conversión</h2>
            <p>Resultados de campañas de marketing.</p>
          </div>
        </div>
        <div
          v-if="tasaConversion.length"
          class="chart-list"
          aria-label="Comparativo de conversión por campaña"
        >
          <div
            v-for="campania in tasaConversion"
            :key="`chart-${campania.id_campania}`"
            class="chart-item"
          >
            <div class="chart-caption">
              <span>{{ campania.nombre_campania }}</span>
              <strong>{{ Number(campania.tasa_conversion_pct || 0).toFixed(2) }}%</strong>
            </div>
            <div
              class="chart-track"
              role="img"
              :aria-label="`Conversión de ${campania.nombre_campania}: ${Number(campania.tasa_conversion_pct || 0).toFixed(2)}%`"
            >
              <span
                class="chart-bar chart-bar--conversion"
                :style="{ width: `${anchoBarraConversion(campania.tasa_conversion_pct)}%` }"
                aria-hidden="true"
              ></span>
            </div>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID campaña</th>
                <th>Campaña</th>
                <th>Total prospectos</th>
                <th>Total ventas</th>
                <th>Tasa de conversión</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="campania in tasaConversion" :key="campania.id_campania">
                <td class="id-cell">#{{ campania.id_campania }}</td>
                <td class="campaign-name">{{ campania.nombre_campania }}</td>
                <td>{{ campania.total_prospectos }}</td>
                <td>{{ campania.total_ventas }}</td>
                <td>
                  <span class="rate-value"
                    >{{ Number(campania.tasa_conversion_pct || 0).toFixed(2) }}%</span
                  >
                </td>
              </tr>
              <tr v-if="!tasaConversion.length">
                <td class="empty-state" colspan="5">
                  {{ cargando ? 'Cargando campañas…' : 'No hay datos de campañas disponibles.' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="panel">
        <div class="section-heading">
          <span class="section-number">04</span>
          <div>
            <h2>Reporte mensual de ventas</h2>
            <p>Ventas e ingresos por vendedor en el mes actual.</p>
          </div>
        </div>
        <div
          v-if="reporteMensual.length"
          class="chart-list"
          aria-label="Ingresos mensuales por vendedor"
        >
          <div
            v-for="fila in reporteMensual"
            :key="`chart-${String(fila.vendedor)}`"
            class="chart-item"
          >
            <div class="chart-caption">
              <span>{{ fila.vendedor }}</span>
              <strong>{{ formatearMoneda(fila.ingreso_total) }}</strong>
            </div>
            <div
              class="chart-track"
              role="img"
              :aria-label="`Ingresos de ${fila.vendedor}: ${formatearMoneda(fila.ingreso_total)}`"
            >
              <span
                class="chart-bar chart-bar--ingresos"
                :style="{ width: `${anchoBarraIngreso(fila.ingreso_total)}%` }"
                aria-hidden="true"
              ></span>
            </div>
          </div>
        </div>
        <div v-if="reporteMensual.length" class="table-wrap">
          <table>
            <thead>
              <tr>
                <th v-for="columna in columnasReporte" :key="columna">
                  {{ formatearColumna(columna) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(fila, indice) in reporteMensual" :key="indice">
                <td v-for="(valor, columna) in fila" :key="columna">
                  {{ columna === 'ingreso_total' ? formatearMoneda(valor) : valor }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="empty-report">
          {{ cargando ? 'Cargando reporte…' : 'No hay ventas registradas este mes.' }}
        </p>
      </section>
    </div>
    <footer class="page-footer">Panel de administración · Zimbra</footer>
  </main>
</template>

<style>
:root {
  font-family:
    Inter,
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    'Segoe UI',
    sans-serif;
  color: #172033;
  background: #f4f6fb;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  font-optical-sizing: auto;
}

* {
  box-sizing: border-box;
}

body {
  min-width: 360px;
  min-height: 100vh;
  margin: 0;
  background: radial-gradient(ellipse at 86% 0%, rgb(96 116 238 / 9%), transparent 32rem), #f4f6fb;
}

button {
  font: inherit;
}

.dashboard {
  width: min(1120px, calc(100% - 48px));
  margin: 0 auto;
  padding: 48px 0 28px;
}

.page-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 30px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.session-user {
  color: #69758b;
  font-size: 12px;
}

.logout-button {
  min-height: 42px;
  border: 1px solid #dfe4ef;
  border-radius: 9px;
  padding: 0 14px;
  background: #fff;
  color: #536078;
  cursor: pointer;
}

.persona-status {
  padding: 24px;
}

.eyebrow {
  margin: 0 0 8px;
  color: #5865d8;
  font-size: 11px;
  font-weight: 800;
  letter-spacing: 0.13em;
}

h1,
h2,
p {
  margin-top: 0;
}

h1 {
  margin-bottom: 7px;
  font-size: clamp(28px, 4vw, 36px);
  letter-spacing: -0.045em;
}

.page-description,
.section-heading p {
  margin-bottom: 0;
  color: #778198;
  font-size: 14px;
}

.refresh-button,
.table-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: 0;
  border-radius: 9px;
  color: #fff;
  background: #555ed3;
  font-weight: 650;
  cursor: pointer;
  transition:
    background 150ms ease,
    transform 150ms ease;
}

.refresh-button {
  min-height: 42px;
  padding: 0 16px;
  box-shadow: 0 5px 12px rgb(78 87 197 / 19%);
}

.refresh-button span {
  font-size: 19px;
  line-height: 1;
}

.refresh-button:hover:not(:disabled),
.table-button:hover:not(:disabled) {
  background: #4149bb;
  transform: translateY(-1px);
}

button:disabled {
  cursor: wait;
  opacity: 0.62;
}

.notice {
  margin-bottom: 20px;
  padding: 13px 16px;
  border: 1px solid;
  border-radius: 10px;
  font-size: 14px;
}

.notice--error {
  border-color: #f3c7c7;
  color: #9d2929;
  background: #fff1f0;
}

.notice--exito {
  border-color: #bce6d0;
  color: #176844;
  background: #edfbf3;
}

.loading {
  padding: 16px 0;
  color: #69758b;
  font-size: 14px;
}

.sections {
  display: grid;
  gap: 18px;
}

.panel {
  min-width: 0;
  overflow: hidden;
  border: 1px solid #e8ebf3;
  border-radius: 14px;
  background: #fff;
  box-shadow: 0 5px 18px rgb(29 44 82 / 4%);
}

.section-heading {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 20px 22px 18px;
}

.section-heading > div {
  flex: 1;
  min-width: 0;
}

.section-number {
  display: grid;
  width: 38px;
  height: 38px;
  flex: 0 0 38px;
  place-items: center;
  border-radius: 10px;
  color: #565fd1;
  background: #f0f1ff;
  font-size: 12px;
  font-weight: 800;
}

.section-heading h2 {
  margin-bottom: 4px;
  font-size: 16px;
  letter-spacing: -0.015em;
}

.section-heading p {
  font-size: 12px;
}

.count-badge {
  display: inline-grid;
  min-width: 30px;
  height: 27px;
  place-items: center;
  padding: 0 8px;
  border-radius: 20px;
  color: #535dc9;
  background: #f0f1ff;
  font-size: 12px;
  font-weight: 750;
}

.table-wrap {
  width: 100%;
  overflow-x: auto;
  border-top: 1px solid #edf0f5;
}

.chart-list {
  display: grid;
  gap: 14px;
  padding: 18px 22px;
  border-top: 1px solid #edf0f5;
}

.chart-item {
  display: grid;
  gap: 7px;
}

.chart-caption {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px;
  color: #536078;
  font-size: 12px;
}

.chart-caption strong {
  color: #263b78;
  font-variant-numeric: tabular-nums;
}

.chart-track {
  height: 9px;
  overflow: hidden;
  border-radius: 999px;
  background: #edf0f7;
}

.chart-bar {
  display: block;
  height: 100%;
  border-radius: inherit;
  transition: width 250ms ease;
}

.chart-bar--conversion {
  background: linear-gradient(90deg, #39a27b, #70cba6);
}

.chart-bar--ingresos {
  background: linear-gradient(90deg, #555ed3, #8790f4);
}

table {
  width: 100%;
  border-collapse: collapse;
  text-align: left;
  white-space: nowrap;
}

th,
td {
  padding: 12px 22px;
  border-bottom: 1px solid #edf0f5;
  font-size: 13px;
}

th {
  color: #788198;
  background: #fafbfe;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.025em;
}

td {
  color: #4a556b;
}

tbody tr:last-child td {
  border-bottom: 0;
}

.id-cell {
  color: #717a90;
  font-variant-numeric: tabular-nums;
}

.amount-cell {
  color: #263b78;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

.action-column {
  text-align: right;
}

.table-button {
  min-height: 32px;
  padding: 0 11px;
  font-size: 12px;
}

.empty-state,
.empty-report {
  padding: 19px 22px;
  color: #8790a3;
  font-size: 13px;
  text-align: center;
}

.empty-report {
  margin: 0;
  border-top: 1px solid #edf0f5;
}

.campaign-name {
  min-width: 190px;
  color: #323c53;
  font-weight: 600;
}

.rate-value {
  display: inline-block;
  min-width: 64px;
  color: #366e58;
  font-weight: 750;
  font-variant-numeric: tabular-nums;
}

.page-footer {
  padding-top: 22px;
  color: #9aa2b2;
  font-size: 11px;
  text-align: center;
}

@media (max-width: 640px) {
  .dashboard {
    width: min(100% - 28px, 1120px);
    padding-top: 30px;
  }

  .page-header {
    align-items: flex-start;
  }

  .refresh-button {
    min-height: 38px;
    padding: 0 11px;
    font-size: 12px;
  }

  .section-heading {
    gap: 10px;
    padding: 17px 15px;
  }

  .section-number {
    width: 33px;
    height: 33px;
    flex-basis: 33px;
  }

  .section-heading h2 {
    font-size: 14px;
  }

  .section-heading p {
    font-size: 11px;
    line-height: 1.4;
  }

  th,
  td {
    padding: 11px 15px;
  }
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    scroll-behavior: auto !important;
    transition-duration: 0.01ms !important;
  }
}
</style>
