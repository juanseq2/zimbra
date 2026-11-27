-- Migración de autenticación y personas naturales para Zimbra.
-- Ejecutar UNA sola vez después de hacer respaldo de la base.

ALTER TABLE usuario_sistema
    ADD COLUMN password_hash VARCHAR(255) NULL AFTER email,
    ADD COLUMN ultimo_acceso TIMESTAMP NULL AFTER activo,
    ADD COLUMN fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER ultimo_acceso;

CREATE TABLE IF NOT EXISTS cliente_persona_natural (
    id_persona INT NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(120) NOT NULL,
    correo_electronico VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    telefono VARCHAR(30),
    tipo_identificacion VARCHAR(20),
    numero_identificacion VARCHAR(30),
    plan_servicio VARCHAR(80) NOT NULL,
    estado_solicitud VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_persona),
    UNIQUE KEY uq_persona_natural_correo (correo_electronico),
    CONSTRAINT chk_persona_identificacion CHECK (
        tipo_identificacion IS NULL
        OR tipo_identificacion IN ('CC', 'CE', 'Pasaporte', 'Otro')
    ),
    CONSTRAINT chk_persona_estado CHECK (
        estado_solicitud IN ('pendiente', 'contactada', 'activada', 'rechazada')
    )
) ENGINE=InnoDB;
