# API de Zimbra (MySQL en Aiven)

## Preparar MySQL

Haz un respaldo de `defaultdb` antes de cambiar el esquema. Para una base que ya
tiene las tablas anteriores, ejecuta una sola vez
`database\migracion-funcional-mysql.sql` con una cuenta administradora. Es una
migración aditiva: conserva los registros, agrega asignación/puntaje/actividad
anónima, notificaciones, facturas internas y la cola CRM; también reemplaza
`sp_cerrar_venta` para crear la factura y el evento CRM dentro de la misma
transacción.

Para una instalación nueva, usa `database\zimbra-mysql.sql`; no ejecutes ese
script después de la migración funcional.

Para autenticación y cuentas de persona natural, ejecuta una vez
`database\autenticacion-usuarios-mysql.sql`; para enlazar las solicitudes al
embudo comercial y habilitar el historial, ejecuta después
`database\seguimiento-personas-naturales-mysql.sql`. En una base existente que ya
tenga autenticación, aplica solo la segunda migración. Después configura los
permisos de la cuenta dedicada con `database\roles-permisos-mysql.sql` (ajusta
`defaultdb` si `DB_NAME` es distinto). No compartas ni subas credenciales.

La migración no se ejecuta al arrancar la API y no borra filas. La tabla de
facturas contiene comprobantes internos del sistema; no sustituye una factura
fiscal ni integra un proveedor de facturación electrónica.

## Configuración e inicio

Copia `.env.example` a `.env` en esta carpeta y completa las credenciales privadas
de Aiven. No subas `.env` al repositorio.

```powershell
npm install
npm start
```

La API comprueba la conexión al iniciar. `http://localhost:3000/api/health` debe
responder `{"status":"ok","database":"connected"}`. Para iniciar Vue y la API
juntos, desde `zimbra\` ejecuta `npm run dev:all`.

## Flujo funcional

- Registra prospectos con una prueba de 60 días, validación de correo y captura
  de IP en el registro.
- El registro de persona natural crea también un prospecto, pide compañía y
  permite consultar el estado y las notas del proceso desde su cuenta.
- El administrador puede crear, consultar, actualizar y archivar solicitudes
  personales; archivar desactiva la cuenta y conserva el historial y prospecto.
- Registra navegación anónima mediante un identificador temporal de sesión del
  navegador; al registrarse el prospecto, asocia esos eventos. Los eventos
  anónimos no asociados se conservan en la base; elimínalos solo con una política
  de retención acordada.
- El puntaje suma 5 por visita, 20 por página de precios, 25 por solicitar demo,
  15 por propuesta enviada y 30 por propuesta aceptada, hasta un máximo de 100.
  Al alcanzar `PUNTAJE_MINIMO_ASIGNACION` (50 por defecto), asigna al vendedor
  activo con menos prospectos y crea una notificación. El máximo por vendedor se
  controla con `LIMITE_PROSPECTOS_VENDEDOR` (30 por defecto).
- Los vendedores deben existir en `usuario_sistema` con rol `vendedor` y estar
  activos. El panel permite registrar prospectos, calificar/seguir actividad,
  asignar vendedor, gestionar propuestas y cerrar una propuesta aceptada.
- La creación/asignación de prospectos y los cambios de propuestas generan
  eventos en la cola CRM. El cierre serializa la propuesta con
  `SELECT ... FOR UPDATE`, crea la venta y el comprobante interno, y agrega el
  evento de cierre en la misma transacción.
- Los fallos de entrega quedan visibles y se reintentan; tras ocho intentos se
  pueden reactivar desde el panel.

## CRM / Salesforce

Configura `CRM_WEBHOOK_URL` con un endpoint HTTPS que acepte eventos JSON
(por ejemplo, un Salesforce Flow expuesto por HTTP o un middleware conectado a
Salesforce). Opcionalmente configura `CRM_WEBHOOK_TOKEN`; la API lo envía como
`Authorization: Bearer`. Cada evento incluye un `Idempotency-Key` para evitar
duplicados en el receptor. El receptor debe validar el token e implementar esa
clave de idempotencia.

Sin webhook configurado, el cierre local de ventas sigue funcionando y el evento
queda en `crm_outbox` con estado pendiente de configuración. No se simula una
sincronización exitosa. Una integración nativa con Salesforce requiere además
sus credenciales OAuth, permisos y mapeo de objetos; no están incluidos en el
repositorio.

## Uso seguro

La aplicación tiene login con JWT y acciones administrativas limitadas al rol
administrador, pero todavía requiere una revisión de seguridad para producción.
No publiques la API ni el panel en Internet sin usar un `JWT_SECRET` privado,
HTTPS, controles de acceso completos y protección de secretos. CORS no reemplaza
autenticación.

## Concurrencia y sustentación

La lógica de bloqueo se implementa en `sp_cerrar_venta` con una transacción y
`SELECT ... FOR UPDATE`. Para demostrar el bloqueo sin crear ventas, sigue
`database\guia-sustentacion.md`.
