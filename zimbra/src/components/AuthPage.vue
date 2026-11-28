<script setup lang="ts">
import { ref } from 'vue'

interface UsuarioSesion {
  id: number
  nombre: string
  correo: string
  rol: string
}

const props = defineProps<{ apiUrl: string }>()
const emit = defineEmits<{
  autenticado: [payload: { token: string; usuario: UsuarioSesion }]
}>()

const vista = ref<'interno' | 'persona'>('interno')
const modoPersona = ref<'registro' | 'login'>('registro')
const cargando = ref(false)
const error = ref('')
const exito = ref('')

const interno = ref({ correo_electronico: '', password: '' })
const persona = ref({
  nombre: '',
  empresa: '',
  correo_electronico: '',
  password: '',
  telefono: '',
  tipo_identificacion: '',
  numero_identificacion: '',
  plan_servicio: '',
})

const solicitar = async (ruta: string, cuerpo: object) => {
  const respuesta = await fetch(`${props.apiUrl}/${ruta}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(cuerpo),
  })
  const datos = await respuesta.json()
  if (!respuesta.ok) throw new Error(datos.error || 'No fue posible completar la operación.')
  return datos as { token: string; usuario: UsuarioSesion; mensaje?: string }
}

const iniciarInterno = async () => {
  cargando.value = true
  error.value = ''
  exito.value = ''
  try {
    const resultado = await solicitar('auth/login', interno.value)
    emit('autenticado', resultado)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible iniciar sesión.'
  } finally {
    cargando.value = false
  }
}

const enviarPersona = async () => {
  cargando.value = true
  error.value = ''
  exito.value = ''
  try {
    const ruta = modoPersona.value === 'registro'
      ? 'personas-naturales/registro'
      : 'personas-naturales/login'
    const cuerpo = modoPersona.value === 'registro'
      ? persona.value
      : { correo_electronico: persona.value.correo_electronico, password: persona.value.password }
    const resultado = await solicitar(ruta, cuerpo)
    exito.value = resultado.mensaje || 'Sesión iniciada.'
    emit('autenticado', resultado)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'No fue posible completar el registro.'
  } finally {
    cargando.value = false
  }
}
</script>

<template>
  <main class="auth-shell">
    <section class="auth-card">
      <div class="auth-brand">
        <p>ZIMBRA · VENTAS</p>
        <h1>Bienvenido</h1>
      </div>

      <div class="auth-tabs">
        <button type="button" :class="{ active: vista === 'interno' }" @click="vista = 'interno'">
          Acceso administrativo
        </button>
        <button type="button" :class="{ active: vista === 'persona' }" @click="vista = 'persona'">
          Persona natural
        </button>
      </div>

      <p v-if="error" class="auth-message auth-error">{{ error }}</p>
      <p v-if="exito" class="auth-message auth-success">{{ exito }}</p>

      <form v-if="vista === 'interno'" class="auth-form" @submit.prevent="iniciarInterno">
        <label>
          Correo electrónico
          <input v-model.trim="interno.correo_electronico" type="email" autocomplete="username" required />
        </label>
        <label>
          Contraseña
          <input v-model="interno.password" type="password" autocomplete="current-password" required />
        </label>
        <button type="submit" :disabled="cargando">
          {{ cargando ? 'Ingresando…' : 'Iniciar sesión' }}
        </button>
      </form>

      <div v-else>
        <div class="auth-subtabs">
          <button type="button" :class="{ active: modoPersona === 'registro' }" @click="modoPersona = 'registro'">
            Crear solicitud
          </button>
          <button type="button" :class="{ active: modoPersona === 'login' }" @click="modoPersona = 'login'">
            Iniciar sesión
          </button>
        </div>

        <form class="auth-form" @submit.prevent="enviarPersona">
          <template v-if="modoPersona === 'registro'">
            <label>
              Nombre completo
              <input v-model.trim="persona.nombre" maxlength="120" autocomplete="name" required />
            </label>
            <label>
              Compañía
              <input v-model.trim="persona.empresa" maxlength="120" autocomplete="organization" required />
            </label>
          </template>
          <label>
            Correo electrónico
            <input v-model.trim="persona.correo_electronico" type="email" autocomplete="email" required />
          </label>
          <label>
            Contraseña
            <input v-model="persona.password" type="password" minlength="8" maxlength="72" autocomplete="new-password" required />
          </label>
          <template v-if="modoPersona === 'registro'">
            <label>
              Teléfono
              <input v-model.trim="persona.telefono" maxlength="30" autocomplete="tel" />
            </label>
            <label>
              Tipo de identificación
              <select v-model="persona.tipo_identificacion">
                <option value="">Seleccionar</option>
                <option value="CC">Cédula de ciudadanía</option>
                <option value="CE">Cédula de extranjería</option>
                <option value="Pasaporte">Pasaporte</option>
                <option value="Otro">Otro</option>
              </select>
            </label>
            <label>
              Número de identificación
              <input v-model.trim="persona.numero_identificacion" maxlength="30" />
            </label>
            <label>
              Servicio
              <select v-model="persona.plan_servicio" required>
                <option value="">Seleccionar servicio</option>
                <option value="Prueba gratuita 60 días">Prueba gratuita 60 días</option>
                <option value="Plan mensual">Plan mensual</option>
                <option value="Plan empresarial">Plan empresarial</option>
              </select>
            </label>
          </template>
          <button type="submit" :disabled="cargando">
            {{ cargando ? 'Procesando…' : modoPersona === 'registro' ? 'Solicitar servicio' : 'Ingresar' }}
          </button>
        </form>
      </div>
    </section>
  </main>
</template>

<style scoped>
.auth-shell { min-height: 100vh; display:grid; place-items:center; padding:24px; background:radial-gradient(circle at 80% 0%,#dfe3ff 0,transparent 30rem),#f4f6fb; }
.auth-card { width:min(520px,100%); border:1px solid #e3e7f1; border-radius:18px; background:#fff; padding:30px; box-shadow:0 18px 50px rgba(29,44,82,.10); }
.auth-brand p { margin:0 0 6px; color:#5865d8; font-size:11px; font-weight:800; letter-spacing:.13em; }
.auth-brand h1 { margin:0 0 22px; font-size:32px; }
.auth-tabs,.auth-subtabs { display:flex; gap:8px; margin-bottom:18px; }
.auth-tabs button,.auth-subtabs button { flex:1; border:1px solid #e3e7f1; border-radius:9px; background:#fff; color:#64708a; min-height:42px; cursor:pointer; }
.auth-tabs button.active,.auth-subtabs button.active { border-color:#555ed3; background:#f0f1ff; color:#4149bb; font-weight:700; }
.auth-form { display:grid; gap:14px; }
.auth-form label { display:grid; gap:7px; color:#536078; font-size:13px; font-weight:700; }
.auth-form input,.auth-form select { width:100%; height:44px; border:1px solid #dfe4ef; border-radius:9px; padding:0 12px; background:#fff; color:#172033; }
.auth-form button { height:44px; border:0; border-radius:9px; background:#555ed3; color:#fff; font-weight:800; cursor:pointer; }
.auth-form button:disabled { opacity:.65; cursor:wait; }
.auth-message { border-radius:9px; padding:12px; font-size:13px; }
.auth-error { background:#fff1f0; color:#9d2929; border:1px solid #f3c7c7; }
.auth-success { background:#edfbf3; color:#176844; border:1px solid #bce6d0; }
</style>
