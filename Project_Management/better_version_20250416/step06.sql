/*==================================================================
 步骤6：创建每日记录表
==================================================================*/
-- 每日工作状态历史记录（原始记录）
CREATE TABLE daily_work_history (
    day_number INT,         -- 模拟天数
    floor INT,              -- 楼层
    process TEXT,           -- 工序
    trade TEXT,             -- 工种
    planned_remaining INT,  -- 计划剩余量
    actual_done INT,        -- 当日实际完成量
    is_valid BOOLEAN,       -- 是否有效日（无效日完成量为0）
    recorded_at TIMESTAMPTZ DEFAULT NOW(),  -- 记录时间
    PRIMARY KEY (day_number, floor, process)
);

-- 每日任务详细记录（含扰动、返工、效率等详细信息）
CREATE TABLE daily_task_record (
    day_number INT,
    process TEXT,
    floor INT,
    trade TEXT,
    is_invalid BOOLEAN,       -- 是否为无效日（10%概率）
    is_rework BOOLEAN,        -- 是否为返工（任务重启）
    daily_work_done INT,      -- 当日完成工作量
    efficiency TEXT,          -- 效率百分比（对比理论最大值）
    start_day INT,            -- 任务启动日
    complete_day INT,         -- 任务完成日（未完成则为NULL）
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (day_number, process, floor)
);