-- ============================================================
-- 016_p2p_signaling.sql
-- P2P 信令系统：WebRTC 信令通道、节点注册、分发记录
-- ============================================================
-- 说明：
--   - 创建 WebRTC 信令通道表，管理 offer/answer/ICE 候选交换
--   - 创建 P2P 节点注册表，管理在线用户作为分发节点
--   - 创建 P2P 分发记录表，记录节点间数据传输日志
--   - 支持带宽评分，用于选择最优分发节点
--   - 提供过期信令和失活节点的自动清理函数
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- WebRTC 信令通道
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS p2p_signal_channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id         VARCHAR(100) NOT NULL,                   -- 房间ID（通常为视频ID）
    peer_id         VARCHAR(100) NOT NULL,                   -- 对等节点ID
    fingerprint_id  UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    signal_type     VARCHAR(20) NOT NULL,                    -- offer/answer/ice-candidate
    sdp_data        TEXT,                                    -- SDP 描述
    ice_candidate   JSONB,                                   -- ICE 候选
    target_peer_id  VARCHAR(100),                            -- 目标节点ID
    ttl             INT DEFAULT 30,                          -- 信令存活秒数
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE p2p_signal_channels IS 'WebRTC P2P 信令通道表：管理节点间的信令交换';
COMMENT ON COLUMN p2p_signal_channels.id IS 'UUID v4 主键';
COMMENT ON COLUMN p2p_signal_channels.room_id IS '房间 ID（通常为视频 ID）';
COMMENT ON COLUMN p2p_signal_channels.peer_id IS '发送信令的对等节点 ID';
COMMENT ON COLUMN p2p_signal_channels.fingerprint_id IS '关联的设备指纹 ID';
COMMENT ON COLUMN p2p_signal_channels.signal_type IS '信令类型：offer(邀请)/answer(应答)/ice-candidate(ICE候选)';
COMMENT ON COLUMN p2p_signal_channels.sdp_data IS 'SDP 会话描述协议数据';
COMMENT ON COLUMN p2p_signal_channels.ice_candidate IS 'ICE 候选信息（JSON 格式）';
COMMENT ON COLUMN p2p_signal_channels.target_peer_id IS '目标节点 ID（信令接收方）';
COMMENT ON COLUMN p2p_signal_channels.ttl IS '信令存活秒数（默认 30 秒）';

-- -----------------------------------------------------------
-- P2P 节点注册表（在线用户作为分发节点）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS p2p_peer_registry (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    peer_id             VARCHAR(100) NOT NULL,               -- 对等节点ID
    fingerprint_id      UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    ip_address          INET,                                -- 节点 IP 地址
    region              VARCHAR(50),                         -- 地区
    is_active           BOOLEAN DEFAULT TRUE,
    current_video_id    UUID,                                -- 当前观看的视频ID
    bandwidth_score     INT DEFAULT 0,                       -- 带宽评分 0-100
    last_heartbeat      TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- 最后心跳时间
    connected_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- 连接时间
    disconnected_at     TIMESTAMPTZ,                         -- 断开时间

    CONSTRAINT uq_p2p_peer_registry_peer_id UNIQUE (peer_id)
);

COMMENT ON TABLE p2p_peer_registry IS 'P2P 在线节点注册表：管理在线用户作为分发节点';
COMMENT ON COLUMN p2p_peer_registry.id IS 'UUID v4 主键';
COMMENT ON COLUMN p2p_peer_registry.peer_id IS '对等节点 ID（唯一）';
COMMENT ON COLUMN p2p_peer_registry.fingerprint_id IS '关联的设备指纹 ID';
COMMENT ON COLUMN p2p_peer_registry.ip_address IS '节点 IP 地址';
COMMENT ON COLUMN p2p_peer_registry.region IS '节点所在地区';
COMMENT ON COLUMN p2p_peer_registry.is_active IS '是否在线活跃';
COMMENT ON COLUMN p2p_peer_registry.current_video_id IS '当前正在观看的视频 ID';
COMMENT ON COLUMN p2p_peer_registry.bandwidth_score IS '带宽评分（0-100），用于选择最优分发节点';
COMMENT ON COLUMN p2p_peer_registry.last_heartbeat IS '最后心跳时间';
COMMENT ON COLUMN p2p_peer_registry.connected_at IS '节点连接时间';
COMMENT ON COLUMN p2p_peer_registry.disconnected_at IS '节点断开时间';

-- -----------------------------------------------------------
-- P2P 分发记录
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS p2p_transfer_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_peer_id  VARCHAR(100) NOT NULL,                   -- 源节点ID
    target_peer_id  VARCHAR(100) NOT NULL,                   -- 目标节点ID
    video_id        UUID,                                    -- 视频 ID
    data_type       VARCHAR(20) DEFAULT 'm3u8',             -- m3u8/ts/danmaku
    data_size_kb    INT DEFAULT 0,                           -- 数据大小（KB）
    transfer_time_ms INT DEFAULT 0,                          -- 传输耗时（毫秒）
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 传输时间
);

COMMENT ON TABLE p2p_transfer_logs IS 'P2P 分发记录表：记录节点间的数据传输日志';
COMMENT ON COLUMN p2p_transfer_logs.source_peer_id IS '源节点 ID（数据发送方）';
COMMENT ON COLUMN p2p_transfer_logs.target_peer_id IS '目标节点 ID（数据接收方）';
COMMENT ON COLUMN p2p_transfer_logs.video_id IS '关联的视频 ID';
COMMENT ON COLUMN p2p_transfer_logs.data_type IS '数据类型：m3u8(播放列表)/ts(视频分片)/danmaku(弹幕)';
COMMENT ON COLUMN p2p_transfer_logs.data_size_kb IS '传输数据大小（KB）';
COMMENT ON COLUMN p2p_transfer_logs.transfer_time_ms IS '传输耗时（毫秒）';
COMMENT ON COLUMN p2p_transfer_logs.created_at IS '传输时间';

-- -----------------------------------------------------------
-- 函数：清理过期信令和失活节点
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION cleanup_expired_signals()
RETURNS VOID AS $$
BEGIN
    -- 清理超过 30 秒的信令
    DELETE FROM p2p_signal_channels WHERE created_at < NOW() - INTERVAL '30 seconds';
    -- 标记超过 60 秒无心跳的节点为失活
    UPDATE p2p_peer_registry SET is_active = FALSE, disconnected_at = NOW()
    WHERE is_active = TRUE AND last_heartbeat < NOW() - INTERVAL '60 seconds';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_signals() IS '清理过期P2P信令（30秒）和失活节点（60秒无心跳）';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- p2p_signal_channels 表索引
CREATE INDEX IF NOT EXISTS idx_p2p_signals_room ON p2p_signal_channels(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_p2p_signals_peer ON p2p_signal_channels(peer_id, created_at);
CREATE INDEX IF NOT EXISTS idx_p2p_signals_target ON p2p_signal_channels(target_peer_id, created_at) WHERE target_peer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_p2p_signals_ttl ON p2p_signal_channels(created_at) WHERE created_at > NOW() - INTERVAL '30 seconds';

-- p2p_peer_registry 表索引
CREATE INDEX IF NOT EXISTS idx_p2p_peers_active ON p2p_peer_registry(is_active, last_heartbeat) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_p2p_peers_video ON p2p_peer_registry(current_video_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_p2p_peers_region ON p2p_peer_registry(region) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_p2p_peers_bandwidth ON p2p_peer_registry(bandwidth_score DESC) WHERE is_active = TRUE;

-- p2p_transfer_logs 表索引
CREATE INDEX IF NOT EXISTS idx_p2p_transfers_source ON p2p_transfer_logs(source_peer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_p2p_transfers_target ON p2p_transfer_logs(target_peer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_p2p_transfers_video ON p2p_transfer_logs(video_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_p2p_transfers_created_at ON p2p_transfer_logs(created_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('016_p2p_signaling.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
