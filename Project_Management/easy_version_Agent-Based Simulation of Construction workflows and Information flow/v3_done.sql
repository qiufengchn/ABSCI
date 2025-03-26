/*==================================================================
 步骤1：清理环境（每次重新运行前必须执行）
==================================================================*/
DROP TABLE IF EXISTS 
    daily_task_record, daily_work_history, task_progress, trade_resource, space, task, 
    dependency, process CASCADE;

DROP VIEW IF EXISTS current_project_status, project_progress_details CASCADE;

/*==================================================================
 步骤2：创建基础表结构（所有数值字段使用整数）
==================================================================*/
-- 工序表（核心基准数据）
CREATE TABLE process (
    process TEXT PRIMARY KEY,
    trade TEXT NOT NULL,
    initial_production_rate INT NOT NULL CHECK (initial_production_rate > 0)
);

-- 依赖关系表
CREATE TABLE dependency (
    predecessor_process TEXT REFERENCES process(process),
    successor_process TEXT REFERENCES process(process),
    PRIMARY KEY (predecessor_process, successor_process)
);

-- 任务表（带±10%随机扰动，结果取整）
CREATE TABLE task (
    process TEXT PRIMARY KEY REFERENCES process(process),
    initial_quantity INT NOT NULL CHECK (initial_quantity > 0)
);

-- 空间表（每个楼层的工作量与任务量相同）
CREATE TABLE space (
    process TEXT REFERENCES task(process),
    floor INT CHECK (floor BETWEEN 1 AND 5),
    quantity INT NOT NULL,
    PRIMARY KEY (process, floor)
);

/*==================================================================
 步骤3：插入基础数据（所有数值保持整数）
==================================================================*/
-- 插入工序数据
INSERT INTO process VALUES
('Gravel base layer',          'Gravel',    34),
('Pipes in the floor',         'Plumbing',  69),
('Electric conduits in the floor', 'Electricity', 51),
('Floor tiling',               'Tiling',    62),
('Partition phase 1',          'Partition', 55),
('Pipes in the wall',          'Plumbing',  37),
('Partition phase 2',          'Partition', 51),
('Electric conduits in the wall', 'Electricity', 41),
('Partition phase 3',          'Partition', 32),
('Wall tiling',                'Tiling',    27);

-- 插入带扰动的任务数据（ROUND确保整数）
INSERT INTO task 
SELECT 
    process, 
    ROUND(initial_quantity * (0.9 + 0.2 * random()))::INT
FROM (VALUES
    ('Gravel base layer',          170),
    ('Pipes in the floor',         100),
    ('Electric conduits in the floor', 80),
    ('Floor tiling',              720),
    ('Partition phase 1',         750),
    ('Pipes in the wall',         190),
    ('Partition phase 2',          20),
    ('Electric conduits in the wall', 180),
    ('Partition phase 3',         200),
    ('Wall tiling',               290)
) AS raw_data(process, initial_quantity);

-- 插入依赖关系（保持不变）
INSERT INTO dependency VALUES
('Gravel base layer', 'Pipes in the floor'),
('Gravel base layer', 'Electric conduits in the floor'),
('Pipes in the floor', 'Floor tiling'),
('Electric conduits in the floor', 'Floor tiling'),
('Partition phase 1', 'Pipes in the wall'),
('Pipes in the wall', 'Partition phase 2'),
('Partition phase 2', 'Electric conduits in the wall'),
('Electric conduits in the wall', 'Partition phase 3'),
('Partition phase 3', 'Wall tiling');

-- 生成空间数据（每个楼层的工作量=任务总量）
INSERT INTO space 
SELECT 
    t.process, 
    f.floor, 
    t.initial_quantity
FROM task t
CROSS JOIN generate_series(1, 5) AS f(floor);

/*==================================================================
 步骤4：创建资源与任务进度跟踪表
==================================================================*/
-- 工种资源表
CREATE TABLE trade_resource (
    trade TEXT PRIMARY KEY,
    available_workers INT DEFAULT 1 CHECK (available_workers >= 1),
    status TEXT DEFAULT 'available' CHECK (status IN ('available','busy'))
);

-- 任务进度表（核心跟踪表）
CREATE TABLE task_progress (
    process TEXT REFERENCES process(process),
    floor INT,
    remaining_quantity INT CHECK (remaining_quantity >= 0),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending','in_progress','completed')),
    start_day INT,
    last_update_day INT,
    assigned_trade TEXT REFERENCES trade_resource(trade),
    planned_remaining INT,  -- 初始计划值
    daily_productivity INT,  -- 实际日效率
    PRIMARY KEY (process, floor)
);

-- 初始化工种资源
INSERT INTO trade_resource (trade) VALUES 
('Gravel'), ('Plumbing'), ('Electricity'), ('Tiling'), ('Partition');

-- 初始化任务进度（每个空间单元一个任务记录）
INSERT INTO task_progress (
    process, floor, remaining_quantity, 
    assigned_trade, planned_remaining
)
SELECT 
    s.process, 
    s.floor, 
    s.quantity,
    p.trade,
    s.quantity
FROM space s
JOIN process p USING (process);

/*==================================================================
 步骤5：创建更新任务进度的函数（增加楼层先后顺序判断）
==================================================================*/
-- 启动新任务（严格按照楼层和工序顺序启动，即只有低楼层完成后，高楼层才能启动）
CREATE OR REPLACE FUNCTION update_task_progress(current_day INT)
RETURNS void AS $$
DECLARE
    task_record RECORD;
    assigned_trades TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOR task_record IN (
        SELECT 
            tp.process,
            tp.floor,
            tp.assigned_trade
        FROM task_progress tp
        WHERE tp.status = 'pending'
          AND NOT EXISTS (
              SELECT 1 
              FROM dependency d
              JOIN task_progress tp2 ON d.predecessor_process = tp2.process
              WHERE d.successor_process = tp.process
                AND tp2.floor = tp.floor 
                AND tp2.status != 'completed'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM task_progress lower_tp 
              WHERE lower_tp.process = tp.process
                AND lower_tp.floor < tp.floor
                AND lower_tp.status != 'completed'
          )
          AND EXISTS (
              SELECT 1 
              FROM trade_resource tr
              WHERE tr.trade = tp.assigned_trade
                AND tr.status = 'available'
          )
        ORDER BY tp.floor, tp.process
    )
    LOOP
        IF NOT task_record.assigned_trade = ANY(assigned_trades) THEN
            UPDATE task_progress
            SET 
                status = 'in_progress',
                start_day = current_day,
                last_update_day = current_day
            WHERE process = task_record.process
              AND floor = task_record.floor;

            UPDATE trade_resource
            SET status = 'busy'
            WHERE trade = task_record.assigned_trade;

            assigned_trades := array_append(assigned_trades, task_record.assigned_trade);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

/*==================================================================
 步骤6：创建每日记录表
==================================================================*/
-- 每日工作状态历史记录（原始记录）
CREATE TABLE daily_work_history (
    day_number INT,
    floor INT,
    process TEXT,
    trade TEXT,
    planned_remaining INT,
    actual_done INT,
    is_valid BOOLEAN,
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (day_number, floor, process)
);

-- 每日任务详细记录（记录扰动、返工、当日工作、效率、任务启动和完成时间）
CREATE TABLE daily_task_record (
    day_number INT,
    process TEXT,
    floor INT,
    trade TEXT,
    is_invalid BOOLEAN,       -- 扰动标记：是否为无效日
    is_rework BOOLEAN,        -- 返工标记：任务启动日早于当前日即为返工
    daily_work_done INT,      -- 当日完成工作量
    efficiency TEXT,          -- 工作效率（百分比）
    start_day INT,            -- 任务启动日
    complete_day INT,         -- 任务完成日（未完成为 NULL）
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (day_number, process, floor)
);

/*==================================================================
 步骤7：扩展处理每日工作的函数（记录每日详细信息）
==================================================================*/
CREATE OR REPLACE FUNCTION process_work_day(current_day INT)
RETURNS void AS $$
DECLARE
    task_rec RECORD;
    work_done INT;
    is_invalid BOOLEAN;
    new_remaining INT;
    eff NUMERIC(10,2);
    is_rework BOOLEAN;
BEGIN
    FOR task_rec IN (
        SELECT 
            tp.*,
            p.initial_production_rate,
            tr.available_workers
        FROM task_progress tp
        JOIN process p ON tp.process = p.process
        JOIN trade_resource tr ON tp.assigned_trade = tr.trade
        WHERE tp.status = 'in_progress'
    )
    LOOP
        -- 生成10%无效日概率（扰动数据）
        is_invalid := (random() < 0.1);
        
        -- 计算实际效率（±10%扰动，确保至少1单位）
        work_done := CASE 
            WHEN is_invalid THEN 0
            ELSE GREATEST(1, ROUND(task_rec.initial_production_rate * (0.9 + 0.2 * random())) * task_rec.available_workers)
        END;
        
        -- 计算更新后剩余工作量
        new_remaining := CASE 
            WHEN task_rec.remaining_quantity <= work_done THEN 0 
            ELSE task_rec.remaining_quantity - work_done 
        END;
        
        -- 更新任务进度
        UPDATE task_progress
        SET 
            remaining_quantity = new_remaining,
            last_update_day = current_day,
            daily_productivity = work_done,
            status = CASE 
                        WHEN new_remaining = 0 THEN 'completed'
                        ELSE 'in_progress'
                     END
        WHERE process = task_rec.process AND floor = task_rec.floor;
        
        -- 若任务完成则释放工种资源
        IF new_remaining = 0 THEN
            UPDATE trade_resource
            SET status = 'available'
            WHERE trade = task_rec.assigned_trade;
        END IF;
        
        -- 判断是否为返工（任务启动日早于当前日即为返工）
        is_rework := (task_rec.start_day IS NOT NULL AND task_rec.start_day < current_day);
        
        -- 计算工作效率，基于理论最大产能（initial_production_rate * available_workers）
        IF (task_rec.initial_production_rate * task_rec.available_workers) > 0 THEN
            eff := ROUND((work_done::NUMERIC / (task_rec.initial_production_rate * task_rec.available_workers)) * 100, 2);
        ELSE
            eff := 0;
        END IF;
        
        -- 将当日任务详细记录插入 daily_task_record 表
        INSERT INTO daily_task_record (
            day_number, process, floor, trade, 
            is_invalid, is_rework, daily_work_done, efficiency, 
            start_day, complete_day
        ) VALUES (
            current_day,
            task_rec.process,
            task_rec.floor,
            task_rec.assigned_trade,
            is_invalid,
            is_rework,
            work_done,
            eff::TEXT || '%',
            task_rec.start_day,
            CASE WHEN new_remaining = 0 THEN current_day ELSE NULL END
        );
    END LOOP;
    
    -- 启动当天可以执行的新任务
    PERFORM update_task_progress(current_day);
END;
$$ LANGUAGE plpgsql;

/*==================================================================
 步骤8：执行模拟
==================================================================*/
DO $$
DECLARE 
    current_day INTEGER := 0;
    max_days INTEGER := 365; -- 最大模拟天数
BEGIN
    TRUNCATE TABLE daily_work_history;
    TRUNCATE TABLE daily_task_record;
    
    WHILE current_day < max_days LOOP
        -- 记录当日状态到历史记录表
        INSERT INTO daily_work_history (
            day_number, floor, process, trade, 
            planned_remaining, actual_done, is_valid
        )
        SELECT 
            current_day,
            tp.floor,
            tp.process,
            tp.assigned_trade,
            tp.planned_remaining,
            COALESCE(tp.daily_productivity, 0),
            (COALESCE(tp.daily_productivity,0) > 0)
        FROM task_progress tp;
        
        -- 执行当日工作，并记录详细信息
        PERFORM process_work_day(current_day);
        
        -- 检查是否全部任务完成
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM task_progress WHERE status != 'completed'
        );
        current_day := current_day + 1;
    END LOOP;
    
    RAISE NOTICE 'Simulation completed in % days', current_day;
END $$;

/*==================================================================
 步骤9：查看结果
==================================================================*/
-- 查看项目进度视图（新增 Trade Status 列）
CREATE OR REPLACE VIEW project_progress_details AS
SELECT 
    dwh.day_number AS "Day",
    dwh.floor AS "Floor",
    dwh.process AS "Process",
    p.trade AS "Process Trade",
    r.status AS "Trade Status",
    t.initial_quantity AS "Total Work",
    dwh.planned_remaining AS "Plan Remaining",
    dwh.actual_done AS "Daily Done",
    (t.initial_quantity - dwh.planned_remaining) AS "Cumulative Done",
    CASE WHEN dwh.is_valid THEN 'Valid' ELSE 'Invalid' END AS "Validity",
    ROUND(dwh.actual_done::NUMERIC / p.initial_production_rate * 100) || '%' AS "Efficiency",
    tp.status AS "Task Status"
FROM daily_work_history dwh
JOIN task t USING (process)
JOIN process p USING (process)
JOIN task_progress tp ON dwh.process = tp.process AND dwh.floor = tp.floor
JOIN trade_resource r ON tp.assigned_trade = r.trade;

-- 查询最终任务进度
SELECT * FROM task_progress;

-- 查询每日详细记录
SELECT * FROM daily_task_record ORDER BY day_number, process, floor;