# Manual interno — Funcionamiento técnico de Zimbra

## Autenticación y cuentas

La API utiliza bcrypt para almacenar contraseñas y JWT firmado para las sesiones. Los JWT vencen después de ocho horas.

Existen dos tipos de sesión:

- `usuario_interno`: roles `administrador`, `vendedor` e `invitado`.
- `persona_natural`: cuenta pública que solicita o adquiere un servicio.

Los administradores crean usuarios internos mediante `POST /api/usuarios`. Las personas naturales se registran sin acceso al panel comercial mediante `POST /api/personas-naturales/registro`.

## 1. Resumen

Zimbra es una aplicación de demostración comercial compuesta por:

1. Frontend Vue 3 + Vite.
2. API Express.
3. Base de datos MySQL 8.
4. Cola de integración CRM persistida en `crm_outbox`.

El frontend consume la API mediante un prefijo `/api`. En desarrollo, Vite actúa como proxy hacia `http://127.0.0.1:3000`. En producción debe configurarse `VITE_API_URL` o publicar ambos servicios detrás de un reverse proxy.

## 2. Estructura del repositorio

```text
zimbra/
  src/App.vue                         Panel principal
  src/components/ProspectosPanel.vue  Gestión comercial
  server/index.js                     Implementación Express alternativa/antigua
  vite.config.ts                      Proxy y configuración Vite
zimbra-api/
  index.js                            API utilizada por npm run dev:api
  .env.example                        Variables de configuración
database/
  zimbra-mysql.sql                    Esquema completo
  migracion-funcional-mysql.sql       Migración aditiva
  indices-mysql.sql                   Índices auxiliares
  consultas-mysql.sql                 Diagnósticos y consultas
  roles-permisos-mysql.sql            Roles MySQL sugeridos
  guia-sustentacion.md                Procedimiento de demostración
```

El comando `npm run dev:all` iniciado desde `zimbra\` utiliza `zimbra-api\index.js`, no `zimbra\server\index.js`.

## 3. Inicio y ejecución

La API carga variables mediante `dotenv`, crea un pool `mysql2/promise` con diez conexiones y escucha en el puerto definido por `PORT`, con valor 3000.

Al iniciar:

1. Valida conexión con `SELECT 1`.
2. Cierra el proceso si no puede conectarse a MySQL.
3. Intenta un evento CRM pendiente si el webhook está configurado.
4. Programa el procesador de cola cada 15 segundos.

El frontend llama a:

- `/api/prospectos`
- `/api/vendedores`
- `/api/campanias`
- `/api/propuestas`
- `/api/notificaciones`
- `/api/crm/sincronizacion`
- `/api/configuracion`

El componente `App.vue` carga además ventas, propuestas pendientes, conversión y reporte mensual.

## 4. Modelo de datos

### `usuario_sistema`

Usuarios internos con nombre, correo, rol y estado activo. Roles permitidos:

- `administrador`
- `vendedor`
- `invitado`

### `campania_marketing`

Campañas con nombre y canal.

### `cliente_prospecto`

Núcleo del embudo comercial:

- Datos personales y de empresa.
- Estado: `nuevo`, `calificado`, `descartado` o `cliente_comercial`.
- Duración de prueba, por defecto 60 días.
- Puntaje de interés.
- Campaña de origen.
- Vendedor asignado.

Tiene correo único y claves foráneas hacia campaña y vendedor.

### `actividad_web`

Registra eventos asociados a un cliente o eventos anónimos identificados por `visitor_id`. Los tipos permitidos son `page_view`, `visita`, `pagina_precio`, `solicitud_demo` y `descarga_prueba`. La actividad no asociada conserva el identificador del visitante hasta el registro del prospecto.

### `propuesta`

Contiene cliente, vendedor, monto y estado. Estados válidos:

- `borrador`
- `enviada`
- `aceptada`
- `rechazada`

### `venta`

Representa una propuesta cerrada. Tiene restricción única sobre `id_propuesta`, por lo que una propuesta solo puede originar una venta.

### `factura`

Comprobante interno de Zimbra. Está relacionado uno a uno con la venta y tiene número único.

### `crm_outbox`

Cola persistente con:

- Clave de idempotencia única.
- Tipo de evento.
- Payload JSON.
- Estado.
- Intentos.
- Próximo intento.
- Último error.

Estados: `pendiente`, `procesando`, `sincronizado`, `error`.

### `notificacion`

Aviso interno asociado a un usuario y opcionalmente a un cliente.

## 5. Vistas y procedimientos

### `v_tasa_conversion`

Cuenta prospectos únicos y ventas únicas por campaña y obtiene el porcentaje:

```sql
100 * ventas_unicas / prospectos_unicos
```

### `v_reporte_mensual_ventas`

Agrupa ventas del mes calendario actual por vendedor.

### `sp_reporte_mensual_ventas(p_mes, p_anio)`

Versión parametrizada del reporte mensual. Valida mes y año y devuelve vendedor, cantidad de ventas e ingreso total.

### `sp_cerrar_venta`

Implementa el cierre transaccional:

1. Bloquea la propuesta con `SELECT ... FOR UPDATE`.
2. Verifica que exista y esté aceptada.
3. Inserta la venta.
4. Cambia al prospecto a `cliente_comercial`.
5. Crea la factura interna.
6. Crea el evento `venta.cerrada` en `crm_outbox`.
7. Confirma la transacción.

Ante cualquier error SQL, el procedimiento ejecuta `ROLLBACK`.

## 6. Flujo de registro de prospectos

La API valida nombre, correo, empresa, campaña e identificador de visitante. Después abre una transacción:

1. Inserta el cliente con prueba de 60 días.
2. Encola `prospecto.creado`.
3. Inserta la actividad `registro_prueba`.
4. Si existe `visitor_id`, vincula todas las actividades anónimas con ese identificador.
5. Calcula el puntaje sumando las actividades asociadas.
6. Actualiza el puntaje.
7. Intenta asignación automática.
8. Confirma la transacción.

La duplicación de correo genera un error 409. Una campaña inválida genera un error 400 o 1452 según la operación y la restricción.

## 7. Calificación y asignación

El puntaje se calcula con esta lógica:

| Evento | Valor |
|---|---:|
| `registro_prueba` | 5 |
| `page_view` o `visita` | 5 |
| `pagina_precio` | 20 |
| `solicitud_demo` | 25 |
| `descarga_prueba` | 10 |
| `propuesta_enviada` | 15 |
| `propuesta_aceptada` | 30 |

Se limita a 100.

La asignación automática usa `FOR UPDATE` sobre el prospecto y los vendedores. Selecciona el vendedor activo con menor número de prospectos activos. Para contar prospectos activos considera únicamente clientes en estado `nuevo` o `calificado` cuya prueba no ha vencido.

Si el límite impide asignar al prospecto, no se crea la asignación. Una asignación manual valida:

- Existencia del prospecto.
- Existencia y estado activo del vendedor.
- Cupo disponible.

Una asignación exitosa crea una notificación y el evento `prospecto.asignado`.

## 8. Ciclo de propuestas

### Creación

Valida cliente, vendedor y monto. Inserta la propuesta en estado `borrador` y encola `propuesta.creada`.

### Cambio de estado

Bloquea la propuesta y verifica que no tenga venta asociada. Actualiza el estado y encola `propuesta.estado_cambiado`.

Si pasa a `enviada` o `aceptada`:

- Inserta la actividad correspondiente.
- Recalcula el puntaje.
- Actualiza el puntaje del cliente.
- Puede disparar una asignación automática si aún no existe vendedor.

El trigger `trg_actualizar_prospecto` también califica prospectos nuevos cuando una propuesta pasa a `enviada` o `aceptada`. La API aplica además la misma lógica por una razón funcional redundante y transaccional.

## 9. Cierre y concurrencia

La venta usa dos niveles de protección:

- Restricción única `uq_venta_propuesta`.
- Bloqueo de fila `FOR UPDATE` dentro de `sp_cerrar_venta`.

La propuesta queda bloqueada mientras una transacción valida e inserta los registros. Una segunda solicitud espera o recibe el error según el motor y la operación simultánea.

El procedimiento crea venta, factura y evento CRM dentro de la misma transacción. La API no realiza commits parciales manuales.

El archivo `database\guia-sustentacion.md` incluye una prueba segura de bloqueo que usa solo `SELECT ... FOR UPDATE` y no crea ventas.

## 10. Cola CRM

Cada operación relevante inserta eventos en `crm_outbox` dentro de la misma transacción que modifica los datos comerciales.

El procesador selecciona un evento con `FOR UPDATE SKIP LOCKED`, lo marca `procesando`, aumenta el contador e intenta el webhook.

La petición usa:

- `Content-Type: application/json`
- `Idempotency-Key`
- `Authorization: Bearer <token>` si existe token.

El receptor debe validar el token y procesar idempotentemente la clave.

En caso de respuesta incorrecta o timeout:

- El estado vuelve a `pendiente` hasta ocho intentos.
- El próximo intento usa una espera creciente limitada a 60 minutos.
- Al llegar a ocho intentos queda `error`.

Sin webhook configurado no se simula sincronización; los eventos permanecen pendientes.

## 11. API REST

| Método | Ruta | Función |
|---|---|---|
| GET | `/api/health` | Verifica base de datos |
| GET | `/api/configuracion` | Devuelve umbral y límite |
| GET | `/api/campanias` | Lista campañas |
| GET | `/api/vendedores` | Lista vendedores activos y carga |
| GET | `/api/prospectos` | Lista prospectos |
| POST | `/api/prospectos` | Registra prospecto |
| GET | `/api/prospectos/:id/actividades` | Lista actividad |
| PATCH | `/api/prospectos/:id/asignacion` | Asigna vendedor |
| POST | `/api/actividad` | Registra actividad |
| GET | `/api/notificaciones` | Lista notificaciones |
| PATCH | `/api/notificaciones/:id/leida` | Marca aviso leído |
| GET | `/api/propuestas` | Lista propuestas |
| POST | `/api/propuestas` | Crea propuesta |
| PATCH | `/api/propuestas/:id/estado` | Cambia estado |
| GET | `/api/propuestas-pendientes` | Lista propuestas aceptadas pendientes |
| POST | `/api/cerrar-venta` | Cierra venta |
| GET | `/api/crm/sincronizacion` | Estado de cola CRM |
| POST | `/api/crm/sincronizacion/:id/reintentar` | Reactiva evento fallido |
| GET | `/api/reporte-mensual` | Reporte del mes actual |
| GET | `/api/tasa-conversion` | Conversión por campaña |
| GET | `/api/ventas` | Lista ventas |

La API valida IDs positivos, montos, URLs internas, UUID, estados y tamaños. Los errores SQL internos no se exponen al cliente: se registran en servidor y se devuelve un mensaje genérico.

## 12. Frontend

`main.ts` monta la aplicación Vue y Pinina. El router existe pero no define rutas.

`App.vue`:

- Obtiene datos al montar.
- Ejecuta solicitudes en paralelo.
- Muestra estados de carga y errores.
- Permite actualizar el panel.
- Cierra propuestas aceptadas.

`ProspectosPanel.vue`:

- Mantiene el estado local de prospectos, vendedores y propuestas.
- Ejecuta operaciones mediante `fetch`.
- Usa `sessionStorage` para conservar un `visitor_id` por pestaña/sesión.
- Actualiza el contenido después de mutaciones.
- Deshabilita controles durante guardados.

## 13. Variables de entorno

| Variable | Uso |
|---|---|
| `PORT` | Puerto de la API |
| `FRONTEND_URL` | Origen permitido por CORS |
| `DB_HOST` | Host MySQL |
| `DB_PORT` | Puerto MySQL |
| `DB_USER` | Usuario de aplicación |
| `DB_PASSWORD` | Contraseña |
| `DB_NAME` | Base de datos |
| `PUNTAJE_MINIMO_ASIGNACION` | Puntaje mínimo automático |
| `LIMITE_PROSPECTOS_VENDEDOR` | Cupo por vendedor |
| `CRM_WEBHOOK_URL` | Endpoint HTTPS del CRM |
| `CRM_WEBHOOK_TOKEN` | Token Bearer opcional |
| `VITE_API_URL` | URL de API para el build frontend |

## 14. Permisos y seguridad

El archivo `roles-permisos-mysql.sql` define cuentas ejemplo:

- `zimbra_lectura`: consultas de solo lectura.
- `zimbra_operador`: inserción y actualización limitada.
- `zimbra_admin_bd`: administración de esquema.

Adapte los usuarios a los nombres de base reales y no use una cuenta administrativa desde la aplicación.

Limitaciones actuales:

- No hay login ni autorización por rol.
- CORS limita el origen del navegador pero no autentica.
- Las notificaciones no están filtradas por sesión.
- La API devuelve datos de todos los prospectos.

No publique el sistema hasta incorporar autenticación, autorización, HTTPS y gestión segura de secretos.

## 15. Operación y diagnóstico

### Diagnóstico rápido

1. Ejecutar `SELECT 1`.
2. Abrir `/api/health`.
3. Revisar la terminal de Express.
4. Revisar registros de `crm_outbox`.
5. Ejecutar las consultas de `database\consultas-mysql.sql`.

### Migraciones

- Base nueva: ejecutar `zimbra-mysql.sql`.
- Base existente: ejecutar una vez `migracion-funcional-mysql.sql`.
- Nunca ejecutar ambos scripts consecutivamente.
- Hacer respaldo antes de migrar.
- Después ejecutar `indices-mysql.sql` si hace falta.

### Sustentación

`database\guia-sustentacion.md` propone dividir la demostración entre modelo, API, panel y concurrencia. Para demostrar bloqueo sin alterar datos, use las dos sesiones MySQL documentadas en esa guía.
