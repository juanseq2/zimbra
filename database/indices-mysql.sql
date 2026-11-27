-- Crea los índices faltantes sin crear rutinas ni cambiar filas.
-- Ejecutar después de zimbra-mysql.sql en la base seleccionada.

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'usuario_sistema'
       AND seq_in_index = 1 AND non_unique = 0 AND column_name = 'email') > 0,
    'SELECT ''Índice único de usuario ya existe'' AS status',
    'CREATE UNIQUE INDEX uq_usuario_email ON usuario_sistema (email)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'cliente_prospecto'
       AND seq_in_index = 1 AND non_unique = 0 AND column_name = 'correo_electronico') > 0,
    'SELECT ''Índice único de correo ya existe'' AS status',
    'CREATE UNIQUE INDEX uq_cliente_correo ON cliente_prospecto (correo_electronico)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'actividad_web'
       AND index_name = 'idx_actividad_cliente_fecha') > 0,
    'SELECT ''idx_actividad_cliente_fecha ya existe'' AS status',
    'CREATE INDEX idx_actividad_cliente_fecha ON actividad_web (id_cliente, fecha_actividad)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'cliente_prospecto'
       AND index_name = 'idx_cliente_estado') > 0,
    'SELECT ''idx_cliente_estado ya existe'' AS status',
    'CREATE INDEX idx_cliente_estado ON cliente_prospecto (estado_prospecto)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'cliente_prospecto'
       AND index_name = 'idx_cliente_campania') > 0,
    'SELECT ''idx_cliente_campania ya existe'' AS status',
    'CREATE INDEX idx_cliente_campania ON cliente_prospecto (id_campania)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'propuesta'
       AND index_name = 'idx_propuesta_cliente') > 0,
    'SELECT ''idx_propuesta_cliente ya existe'' AS status',
    'CREATE INDEX idx_propuesta_cliente ON propuesta (id_cliente)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'propuesta'
       AND index_name = 'idx_propuesta_usuario') > 0,
    'SELECT ''idx_propuesta_usuario ya existe'' AS status',
    'CREATE INDEX idx_propuesta_usuario ON propuesta (id_usuario)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'propuesta'
       AND index_name = 'idx_propuesta_estado') > 0,
    'SELECT ''idx_propuesta_estado ya existe'' AS status',
    'CREATE INDEX idx_propuesta_estado ON propuesta (estado_propuesta)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'venta'
       AND index_name = 'idx_venta_usuario') > 0,
    'SELECT ''idx_venta_usuario ya existe'' AS status',
    'CREATE INDEX idx_venta_usuario ON venta (id_usuario)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'venta'
       AND index_name = 'idx_venta_fecha') > 0,
    'SELECT ''idx_venta_fecha ya existe'' AS status',
    'CREATE INDEX idx_venta_fecha ON venta (fecha_cierre)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SET @zimbra_index_sql = IF(
    (SELECT COUNT(*) FROM information_schema.statistics
     WHERE table_schema = DATABASE() AND table_name = 'venta'
       AND seq_in_index = 1 AND non_unique = 0 AND column_name = 'id_propuesta') > 0,
    'SELECT ''Índice único de propuesta en venta ya existe'' AS status',
    'CREATE UNIQUE INDEX uq_venta_propuesta ON venta (id_propuesta)'
);
PREPARE zimbra_index_statement FROM @zimbra_index_sql;
EXECUTE zimbra_index_statement;
DEALLOCATE PREPARE zimbra_index_statement;

SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, SEQ_IN_INDEX, COLUMN_NAME
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND TABLE_NAME IN ('actividad_web', 'cliente_prospecto', 'propuesta', 'venta')
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
