import cors from 'cors'
import dotenv from 'dotenv'
import express from 'express'
import mysql from 'mysql2/promise'

dotenv.config()

const app = express()
const apiPort = Number(process.env.API_PORT || 3000)

app.use(cors({ origin: true }))
app.use(express.json())

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'zimbra_db',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
})

app.get('/api/health', async (_request, response, next) => {
  try {
    await pool.query('SELECT 1')
    response.json({ ok: true })
  } catch (error) {
    next(error)
  }
})

app.get('/api/ventas', async (_request, response, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT id_venta, fecha_cierre, monto_final FROM venta ORDER BY fecha_cierre DESC',
    )
    response.json(rows)
  } catch (error) {
    next(error)
  }
})

app.get('/api/propuestas-pendientes', async (_request, response, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT p.id_propuesta, p.id_cliente, p.id_usuario, p.monto_estimado
      FROM propuesta p
      LEFT JOIN venta v ON v.id_propuesta = p.id_propuesta
      WHERE p.estado_propuesta = 'aceptada'
        AND v.id_venta IS NULL
      ORDER BY p.fecha_creacion DESC
    `)
    response.json(rows)
  } catch (error) {
    next(error)
  }
})

app.get('/api/tasa-conversion', async (_request, response, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT id_campania, nombre_campania, total_prospectos, total_ventas, tasa_conversion_pct FROM v_tasa_conversion',
    )
    response.json(rows)
  } catch (error) {
    next(error)
  }
})

app.get('/api/reporte-mensual', async (_request, response, next) => {
  try {
    const now = new Date()
    const [rows] = await pool.query('CALL sp_reporte_mensual_ventas(?, ?)', [
      now.getMonth() + 1,
      now.getFullYear(),
    ])
    response.json(rows[0])
  } catch (error) {
    next(error)
  }
})

app.post('/api/cerrar-venta', async (request, response, next) => {
  const { id_propuesta, id_usuario, monto_final, metodo_pago } = request.body

  if (!Number.isInteger(id_propuesta) || !Number.isInteger(id_usuario) || Number(monto_final) <= 0) {
    response.status(400).json({ error: 'Datos de venta incompletos o inválidos.' })
    return
  }

  const connection = await pool.getConnection()
  try {
    await connection.beginTransaction()
    await connection.query('CALL sp_cerrar_venta(?, ?, ?, ?, @id_venta_generada)', [
      id_propuesta,
      id_usuario,
      monto_final,
      metodo_pago || 'Transferencia Bancaria',
    ])
    const [variables] = await connection.query(
      'SELECT @id_venta_generada AS venta_creada_id',
    )
    await connection.commit()

    response.status(201).json({
      venta_creada_id: variables[0].venta_creada_id,
    })
  } catch (error) {
    await connection.rollback()
    next(error)
  } finally {
    connection.release()
  }
})

app.use((error, _request, response, _next) => {
  console.error(error)
  response.status(500).json({
    error: error?.sqlMessage || 'No fue posible completar la operación.',
  })
})

app.listen(apiPort, '127.0.0.1', () => {
  console.log(`API Zimbra disponible en http://127.0.0.1:${apiPort}/api`)
})
