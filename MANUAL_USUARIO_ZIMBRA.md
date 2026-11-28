# Manual de usuario — Zimbra Ventas

## Acceso al sistema

La pantalla inicial ofrece dos opciones:

- **Acceso administrativo:** disponible para usuarios internos con rol administrador, vendedor o invitado.
- **Persona natural:** permite crear una solicitud de servicio o iniciar sesión con una cuenta personal.

Los usuarios internos deben obtener sus credenciales del administrador. Un administrador puede crear nuevas cuentas desde **Administración de usuarios**.

Al registrarse como persona natural se solicita nombre, compañía, correo, contraseña y servicio. El registro crea la cuenta y, a la vez, un prospecto en el flujo comercial.

## 1. Propósito

Zimbra es un panel administrativo para gestionar la captación y el seguimiento de prospectos. Permite registrar pruebas gratuitas, controlar el interés de cada prospecto, asignar vendedores, crear propuestas, cerrar ventas y consultar resultados comerciales.

El panel muestra también ventas cerradas, campañas, reportes mensuales y el estado de sincronización con un CRM externo.

## 2. Requisitos

- Node.js compatible con los requisitos de `zimbra/package.json`.
- npm.
- Acceso a MySQL 8.0.16 o posterior.
- Navegador moderno.
- Credenciales de MySQL configuradas para la API.

> Importante: aunque hay inicio de sesión y control básico de roles, la aplicación todavía requiere una revisión de seguridad antes de exponerse en Internet.

## 3. Preparación del sistema

### Instalar dependencias

Desde la carpeta del repositorio:

```powershell
cd zimbra
npm install
cd ..\zimbra-api
npm install
```

### Configurar la API

Copia `zimbra-api\.env.example` como `zimbra-api\.env` y completa las variables privadas:

```text
PORT=3000
FRONTEND_URL=http://localhost:5173
DB_HOST=...
DB_PORT=3306
DB_USER=...
DB_PASSWORD=...
DB_NAME=defaultdb
PUNTAJE_MINIMO_ASIGNACION=50
LIMITE_PROSPECTOS_VENDEDOR=30
CRM_WEBHOOK_URL=
CRM_WEBHOOK_TOKEN=
```

No publiques ni compartas el archivo `.env`.

Si la base ya existe, ejecuta una vez `database\migracion-funcional-mysql.sql`. Para una instalación nueva ejecuta `database\zimbra-mysql.sql`. Después, ejecuta `database\indices-mysql.sql` si se requieren los índices auxiliares.

### Iniciar el sistema

Desde `zimbra\`:

```powershell
npm run dev:all
```

El frontend se abre normalmente en `http://localhost:5173`. La API queda en `http://localhost:3000`.

Comprueba la API en `http://localhost:3000/api/health`. Una respuesta correcta incluye:

```json
{"status":"ok","database":"connected"}
```

## 4. Recorrido por el panel

Al abrir la aplicación se cargan automáticamente:

- Prospectos y vendedores.
- Campañas.
- Propuestas.
- Notificaciones.
- Estado de sincronización CRM.
- Ventas, propuestas pendientes, conversión y reporte mensual.

El botón **Actualizar** vuelve a solicitar los datos a la API.

## 5. Registrar un prospecto

En **Registrar prospecto** complete:

- **Nombre:** obligatorio, máximo 120 caracteres.
- **Correo:** obligatorio y válido, máximo 150 caracteres.
- **Empresa:** opcional, máximo 120 caracteres.
- **Campaña:** opcional.

Pulse **Iniciar prueba gratis**.

El registro:

1. Guarda el prospecto.
2. Le asigna una prueba de 60 días.
3. Vincula las visitas anónimas hechas desde la misma sesión del navegador.
4. Registra una actividad inicial.
5. Calcula el puntaje de interés.
6. Puede asignarlo automáticamente a un vendedor disponible.

No se puede registrar dos veces el mismo correo.

## 6. Interpretar el puntaje de interés

La puntuación máxima es 100:

| Actividad | Puntaje |
|---|---:|
| Registro de la prueba | 5 |
| Visita o vista de página | 5 |
| Descarga de prueba | 10 |
| Visita a la página de precios | 20 |
| Solicitud de demo | 25 |
| Propuesta enviada | 15 |
| Propuesta aceptada | 30 |

Cuando el prospecto alcanza el mínimo configurado —50 puntos por defecto— puede asignarse automáticamente al vendedor activo que tenga menos prospectos activos. La asignación automática respeta un máximo de 30 prospectos activos por vendedor por defecto.

El cálculo se vuelve a ejecutar después de registrar actividades o cambiar una propuesta.

## 7. Consultar y registrar actividad

En la tabla de prospectos:

- **Historial** muestra hasta las últimas 100 actividades del prospecto.
- **Precio** registra una visita a `/precios` y suma 20 puntos.
- **Demo** registra una solicitud de demo y suma 25 puntos.

Los botones **Simular visita a precios** y **Simular solicitud de demo**, situados sobre la tabla, realizan el seguimiento sin asociarlo a un prospecto determinado. Si el navegador registra después al usuario con ese mismo identificador de sesión, sus actividades anónimas se vinculan al prospecto.

Las actividades anónimas no asociadas se conservan hasta que se defina una política de retención.

## 8. Asignar vendedores

En la columna **Vendedor**, seleccione una persona del listado. Solo aparecen vendedores activos.

El selector marca una casilla como deshabilitada cuando el vendedor alcanzó el límite configurado y no tenía ya asignado ese prospecto.

La asignación manual crea una notificación interna para el vendedor y un evento en la cola CRM.

## 9. Crear y gestionar propuestas

1. Pulse **Propuesta** en la fila del prospecto.
2. Seleccione el vendedor.
3. Introduzca el monto estimado en USD.
4. Pulse **Guardar borrador**.

La propuesta aparece en la sección **Propuestas y avance de venta** con estado `borrador`.

En la columna **Estado** puede cambiarla a:

- `borrador`
- `enviada`
- `aceptada`
- `rechazada`

Una propuesta enviada suma 15 puntos al prospecto. Una propuesta aceptada suma 30 puntos. Un cambio de estado genera un evento CRM.

Cuando una propuesta ya tiene una venta cerrada, el estado queda bloqueado.

## 10. Cerrar una venta

En **Propuestas pendientes de venta** aparecen únicamente las propuestas aceptadas que aún no tienen venta.

Pulse **Cerrar venta** en la fila correspondiente.

El sistema ejecuta la operación en una transacción: valida la propuesta, registra la venta, cambia el estado comercial del prospecto, crea la factura interna y encola el evento CRM.

La factura creada es un comprobante interno de Zimbra. No reemplaza una factura fiscal ni integra facturación electrónica.

La venta aparecerá en **Ventas registradas** y la propuesta dejará de estar pendiente.

## 11. Consultar informes

### Propuestas pendientes

Lista las propuestas aceptadas sin venta asociada.

### Ventas registradas

Muestra el identificador, fecha y monto final de las ventas cerradas.

### Tasa de conversión

Calcula por campaña:

```text
ventas únicas / prospectos únicos × 100
```

La gráfica representa porcentajes relativos dentro de las campañas disponibles.

### Reporte mensual

Agrupa las ventas del mes actual por vendedor e muestra cantidad e ingreso total.

## 12. Sincronización CRM

Si no hay `CRM_WEBHOOK_URL`, los eventos permanecen pendientes de configuración. Los cierres locales siguen funcionando.

Si existe un webhook HTTPS:

- Los eventos se envían en segundo plano.
- Se usa `CRM_WEBHOOK_TOKEN` como token Bearer cuando está configurado.
- Cada evento incluye una clave de idempotencia.
- La API reintenta fallos hasta ocho intentos.
- Después del octavo intento el evento pasa a estado `error`.

En **Sincronización CRM**, los eventos con error muestran **Reintentar**. Esta acción reinicia su contador y los vuelve a `pendiente`.

La integración incluida usa webhooks. Salesforce u otro CRM nativo requiere credenciales OAuth, permisos y mapeo adicionales.

## 13. Notificaciones

La sección **Notificaciones de asignación** muestra hasta 50 avisos recientes. Cada aviso puede marcarse como leído.

El contador superior indica cuántas notificaciones siguen sin leer.

## 14. Errores frecuentes

| Problema | Acción |
|---|---|
| `No fue posible cargar el panel` | Comprueba que la API esté activa y que `zimbra-api\.env` tenga datos válidos. |
| Health check con error 503 | Revisa conexión y credenciales de MySQL. |
| No aparecen vendedores | Crea usuarios con rol `vendedor` y `activo=TRUE`. |
| Vendedor deshabilitado | Puede haber alcanzado el límite de prospectos activos. |
| Correo duplicado | Cambia el correo o usa el prospecto existente. |
| Propuesta ya tiene venta | No puede modificarse. |
| CRM pendiente | Configure `CRM_WEBHOOK_URL` o acepta que la cola no representa sincronización. |

## 15. Seguimiento de solicitud como persona natural

Después de iniciar sesión se puede consultar el estado del servicio, la compañía, el plan, el puntaje comercial, el asesor asignado y el historial de actualizaciones.

Los estados pueden incluir: solicitud recibida, en revisión, contacto realizado, propuesta enviada, pendiente de pago, servicio activado o rechazada. El historial muestra las notas y fechas ingresadas por el equipo.

## 16. Administración de solicitudes

El administrador cuenta con una sección para crear, consultar y editar solicitudes de personas naturales, actualizar su estado y agregar una nota de seguimiento. **Archivar** es una baja lógica: desactiva el acceso a la cuenta, pero conserva el prospecto y su historial comercial. Las solicitudes archivadas pueden reactivarse.

## 17. Seguridad y operación

- No exponga el puerto de la API a Internet sin autenticación y autorización.
- Use una cuenta MySQL dedicada y permisos mínimos.
- Mantenga respaldos antes de ejecutar migraciones.
- No use datos reales durante demostraciones en una base compartida.
- CORS no sustituye la autenticación.
