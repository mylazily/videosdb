-- ============================================================
-- 006_seed_data.sql
-- 初始种子数据
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 管理员用户
-- 密码: admin123 (bcrypt hash)
-- -----------------------------------------------------------
INSERT INTO users (id, username, password_hash, nickname, email, role, status) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'admin', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', '系统管理员', 'admin@videos.local', 'super_admin', 'active'),
    ('a0000000-0000-0000-0000-000000000002', 'editor', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', '内容编辑', 'editor@videos.local', 'admin', 'active')
ON CONFLICT (username) DO NOTHING;

-- -----------------------------------------------------------
-- 示例视频数据
-- -----------------------------------------------------------
INSERT INTO videos (id, title, sub_title, description, cover_url, category, tags, year, area, language, director, actors, total_episodes, current_episode, score, score_count, view_count, status, published_at) VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        '流浪地球3',
        'The Wandering Earth 3',
        '太阳急速老化，人类启动流浪地球计划的最终阶段，面对前所未有的宇宙危机。',
        'https://img.example.com/cover/lddq3.jpg',
        '电影',
        '科幻,冒险,灾难,国产',
        2026,
        '大陆',
        '普通话',
        '郭帆',
        '吴京,刘德华,李雪健,沙溢,宁理',
        1, 1, 8.5, 152000, 5800000,
        'published',
        NOW() - INTERVAL '30 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        '庆余年 第三季',
        'Joy of Life Season 3',
        '范闲在经历了种种磨难后，终于揭开了身世之谜，踏上了新的征程。',
        'https://img.example.com/cover/qfyn3.jpg',
        '电视剧',
        '古装,权谋,武侠,国产',
        2025,
        '大陆',
        '普通话',
        '孙皓',
        '张若昀,李沁,陈道明,吴刚,辛芷蕾',
        36, 20, 8.2, 98000, 3200000,
        'published',
        NOW() - INTERVAL '15 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000003',
        '进击的巨人 最终季',
        'Attack on Titan Final Season',
        '人类与巨人的最终决战，艾伦发动地鸣，世界面临毁灭的危机。',
        'https://img.example.com/cover/jjdr.jpg',
        '动漫',
        '热血,战斗,奇幻,日本动漫',
        2024,
        '日本',
        '日语',
        '林祐一郎',
        '梶裕贵,石川由依,井上麻里奈',
        16, 16, 9.1, 320000, 8900000,
        'published',
        NOW() - INTERVAL '90 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000004',
        '奥本海默',
        'Oppenheimer',
        '讲述"原子弹之父"罗伯特·奥本海默领导曼哈顿计划开发原子弹的故事。',
        'https://img.example.com/cover/aobhmr.jpg',
        '电影',
        '传记,历史,剧情,欧美',
        2023,
        '美国',
        '英语',
        '克里斯托弗·诺兰',
        '基里安·墨菲,小罗伯特·唐尼,艾米莉·布朗特',
        1, 1, 8.8, 210000, 4200000,
        'published',
        NOW() - INTERVAL '180 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000005',
        '花儿与少年 第六季',
        'Divas Hit the Road Season 6',
        '明星旅行真人秀，七位嘉宾踏上异国之旅。',
        'https://img.example.com/cover/hezsns.jpg',
        '综艺',
        '真人秀,旅行,综艺',
        2025,
        '大陆',
        '普通话',
        '',
        '秦岚,辛芷蕾,迪丽热巴,赵昭仪,王安宇,胡先煦',
        12, 8, 7.5, 45000, 1500000,
        'published',
        NOW() - INTERVAL '7 days'
    )
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------
-- 示例视频播放源
-- -----------------------------------------------------------
INSERT INTO video_sources (video_id, source_name, play_url, play_links, format, sort_order) VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        '量子资源',
        NULL,
        '[
            {"from": "量子资源", "url": "https://cdn.example.com/m3u8/lddq3/quantum/index.m3u8"},
            {"from": "红牛资源", "url": "https://cdn.example.com/m3u8/lddq3/redbull/index.m3u8"},
            {"from": "光速资源", "url": "https://cdn.example.com/m3u8/lddq3/lightspeed/index.m3u8"}
        ]'::JSONB,
        'hls', 1
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        '量子资源',
        NULL,
        '[
            {"from": "量子资源", "url": "https://cdn.example.com/m3u8/qfyn3/quantum/index.m3u8"},
            {"from": "非凡资源", "url": "https://cdn.example.com/m3u8/qfyn3/feifan/index.m3u8"}
        ]'::JSONB,
        'hls', 1
    ),
    (
        'b0000000-0000-0000-0000-000000000003',
        '樱花资源',
        NULL,
        '[
            {"from": "樱花资源", "url": "https://cdn.example.com/m3u8/jjdr/sakura/index.m3u8"},
            {"from": "18动漫", "url": "https://cdn.example.com/m3u8/jjdr/18comic/index.m3u8"}
        ]'::JSONB,
        'hls', 1
    ),
    (
        'b0000000-0000-0000-0000-000000000004',
        '光速资源',
        NULL,
        '[
            {"from": "光速资源", "url": "https://cdn.example.com/m3u8/aobhmr/lightspeed/index.m3u8"},
            {"from": "闪电资源", "url": "https://cdn.example.com/m3u8/aobhmr/lightning/index.m3u8"}
        ]'::JSONB,
        'hls', 1
    ),
    (
        'b0000000-0000-0000-0000-000000000005',
        '量子资源',
        NULL,
        '[
            {"from": "量子资源", "url": "https://cdn.example.com/m3u8/hezsns/quantum/index.m3u8"}
        ]'::JSONB,
        'hls', 1
    )
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------
-- 示例剧集数据（庆余年 第三季）
-- -----------------------------------------------------------
INSERT INTO episodes (id, video_id, title, number, duration, status) VALUES
    ('c0000001-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', '第1集', 1, 2700, 'published'),
    ('c0000001-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', '第2集', 2, 2680, 'published'),
    ('c0000001-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', '第3集', 3, 2720, 'published'),
    ('c0000001-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', '第4集', 4, 2650, 'published'),
    ('c0000001-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000002', '第5集', 5, 2710, 'published'),
    ('c0000001-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000002', '第6集', 6, 2690, 'published'),
    ('c0000001-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-000000000002', '第7集', 7, 2730, 'published'),
    ('c0000001-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-000000000002', '第8集', 8, 2660, 'published')
ON CONFLICT DO NOTHING;

-- 剧集播放源
INSERT INTO episode_sources (episode_id, source_name, play_url, format, sort_order) VALUES
    ('c0000001-0000-0000-0000-000000000001', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep01.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000001', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep01.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000002', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep02.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000002', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep02.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000003', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep03.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000003', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep03.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000004', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep04.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000004', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep04.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000005', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep05.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000005', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep05.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000006', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep06.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000006', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep06.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000007', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep07.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000007', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep07.m3u8', 'hls', 2),
    ('c0000001-0000-0000-0000-000000000008', '量子资源', 'https://cdn.example.com/m3u8/qfyn3/quantum/ep08.m3u8', 'hls', 1),
    ('c0000001-0000-0000-0000-000000000008', '非凡资源', 'https://cdn.example.com/m3u8/qfyn3/feifan/ep08.m3u8', 'hls', 2)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------
-- 示例评论数据
-- -----------------------------------------------------------
INSERT INTO comments (id, video_id, user_id, parent_id, root_id, content, like_count, status) VALUES
    ('d0000001-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', NULL, NULL, '特效太震撼了！国产科幻的巅峰之作', 256, 'approved'),
    ('d0000001-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', NULL, NULL, '剧情紧凑，全程无尿点，强烈推荐', 189, 'approved'),
    ('d0000001-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000001-0000-0000-0000-000000000001', 'd0000001-0000-0000-0000-000000000001', '同意！郭帆导演太厉害了', 45, 'approved'),
    ('d0000001-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', NULL, NULL, '完结撒花！神作无疑', 520, 'approved'),
    ('d0000001-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', NULL, NULL, '张若昀演技在线，剧情比前两季更精彩', 312, 'approved')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------
-- 示例热搜词
-- -----------------------------------------------------------
INSERT INTO search_hots (keyword, count, category) VALUES
    ('流浪地球3', 125000, '电影'),
    ('庆余年第三季', 98000, '电视剧'),
    ('进击的巨人', 86000, '动漫'),
    ('奥本海默', 72000, '电影'),
    ('花儿与少年', 45000, '综艺'),
    ('鬼灭之刃', 68000, '动漫'),
    ('长相思', 56000, '电视剧'),
    ('封神第二部', 43000, '电影'),
    ('三体', 89000, '电视剧'),
    ('灌篮高手', 51000, '动漫')
ON CONFLICT (keyword) DO NOTHING;

-- -----------------------------------------------------------
-- 示例排行榜数据
-- -----------------------------------------------------------
INSERT INTO ranks (video_id, type, score, period_date) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'hot', 9800.5, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000002', 'hot', 8500.2, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000003', 'hot', 7200.8, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000005', 'hot', 5600.3, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000004', 'hot', 4800.1, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000003', 'score', 9100.0, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000004', 'score', 8800.0, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000001', 'score', 8500.0, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000002', 'score', 8200.0, CURRENT_DATE),
    ('b0000000-0000-0000-0000-000000000005', 'score', 7500.0, CURRENT_DATE)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------
-- 示例采集源
-- -----------------------------------------------------------
INSERT INTO collect_sources (id, name, api_url, source_type, category, interval, max_pages, status) VALUES
    (
        'e0000000-0000-0000-0000-000000000001',
        '量子资源',
        'https://api.liziys.com/api.php/provide/vod/',
        'maccms',
        'movie',
        7200,
        50,
        'idle'
    ),
    (
        'e0000000-0000-0000-0000-000000000002',
        '非凡资源',
        'https://cjhd.lk/api.php/provide/vod/',
        'maccms',
        'tv',
        7200,
        50,
        'idle'
    ),
    (
        'e0000000-0000-0000-0000-000000000003',
        '光速资源',
        'https://api.guangsuzy.com/api.php/provide/vod/',
        'maccms',
        'anime',
        10800,
        30,
        'idle'
    ),
    (
        'e0000000-0000-0000-0000-000000000004',
        '红牛资源',
        'https://www.hongniuzy.com/api.php/provide/vod/',
        'maccms',
        'movie',
        7200,
        50,
        'idle'
    ),
    (
        'e0000000-0000-0000-0000-000000000005',
        '樱花动漫',
        'https://www.yhdm.io/api.php/provide/vod/',
        'maccms',
        'anime',
        10800,
        30,
        'idle'
    )
ON CONFLICT (name) DO NOTHING;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('006_seed_data.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
