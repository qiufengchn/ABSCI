---
jupyter:
  language_info:
    name: sql
  nbformat: 4
  nbformat_minor: 2
---

::: {.cell .markdown}
# 第一部分：清理环境
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 第一部分：清理环境
--------------------
-- 删除所有已存在的表和视图，确保从零开始
DROP TABLE IF EXISTS task_progress CASCADE;
DROP TABLE IF EXISTS trade_resource CASCADE;
DROP TABLE IF EXISTS space CASCADE;
DROP TABLE IF EXISTS task CASCADE;
DROP TABLE IF EXISTS dependency CASCADE;
DROP TABLE IF EXISTS process CASCADE;
DROP TABLE IF EXISTS tasks CASCADE;
DROP TABLE IF EXISTS processes CASCADE;
DROP TABLE IF EXISTS process CASCADE;
DROP TABLE IF EXISTS trade CASCADE;
DROP TABLE IF EXISTS trades CASCADE;
DROP TABLE IF EXISTS dependencies CASCADE;
DROP TABLE IF EXISTS daily_status_log CASCADE;
DROP TABLE IF EXISTS project_history CASCADE;
DROP TABLE IF EXISTS taskexecutionlog CASCADE;
DROP TABLE IF EXISTS tim CASCADE;
DROP TABLE IF EXISTS table_name CASCADE;
DROP TABLE IF EXISTS daily_work_history cascade;
DROP VIEW IF EXISTS current_project_status CASCADE;
DROP VIEW IF EXISTS space_summary CASCADE;
```
:::

::: {.cell .markdown}
# 第二部分：创建基础表结构
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 第二部分：创建基础表结构
-------------------------
-- 1. 工序表：存储所有工序信息
CREATE TABLE process (
    process TEXT PRIMARY KEY,
    trade TEXT,                    -- 工种
    initial_production_rate INT    -- 初始生产率（单位/天）
);

-- 2. 依赖关系表：存储工序间的依赖关系
CREATE TABLE dependency (
    predecessor_process TEXT,      -- 前置工序
    successor_process TEXT         -- 后续工序
);

-- 3. 任务表：存储每个工序的基本工作量
CREATE TABLE task (
    process TEXT PRIMARY KEY,
    initial_quantity INT          -- 初始工作量
);

-- 4. 空间表：存储各楼层的工作量分布
CREATE TABLE space (
    process TEXT,
    floor INT,
    quantity INT,
    PRIMARY KEY (process, floor),
    FOREIGN KEY (process) REFERENCES task(process)
);
```
:::

::: {.cell .markdown}
# 第三部分：插入基础数据
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 第三部分：插入基础数据
-------------------------
-- 1. 插入工序数据
INSERT INTO process VALUES
('Electric conduits in the floor', 'Electricity', 51),
('Electric conduits in the wall', 'Electricity', 41),
('Floor tiling', 'Tiling', 62),
('Gravel base layer', 'Gravel', 34),
('Partition phase 1', 'Partition', 55),
('Partition phase 2', 'Partition', 51),
('Partition phase 3', 'Partition', 32),
('Pipes in the floor', 'Plumbing', 69),
('Pipes in the wall', 'Plumbing', 37),
('Wall tiling', 'Tiling', 27);

-- 2. 插入依赖关系
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

-- 3. 插入任务初始工作量
INSERT INTO task VALUES
('Gravel base layer', 170),
('Pipes in the floor', 100),
('Electric conduits in the floor', 80),
('Floor tiling', 720),
('Partition phase 1', 750),
('Pipes in the wall', 190),
('Electric conduits in the wall', 180),
('Partition phase 2', 20),
('Wall tiling', 290),
('Partition phase 3', 200);

-- 4. 为5层楼生成空间数据
INSERT INTO space 
SELECT t.process, f.floor, t.initial_quantity
FROM task t
CROSS JOIN generate_series(1, 5) AS f(floor);
```
:::

::: {.cell .markdown}
# 第四部分：创建进度跟踪系统
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 第四部分：创建进度跟踪系统
---------------------------
-- 1. 创建工种资源表
CREATE TABLE trade_resource (
    trade TEXT PRIMARY KEY,
    available_workers INT DEFAULT 1,  -- 每个工种默认1个工人
    status TEXT DEFAULT 'available'   -- available/busy
);

-- 2. 创建任务进度表
CREATE TABLE task_progress (
    process TEXT,
    floor INT,
    remaining_quantity FLOAT,        -- 剩余工作量
    status TEXT DEFAULT 'pending',   -- pending/in_progress/completed
    start_day INT,                   -- 开始天数
    last_update_day INT,            -- 最后更新天数
    assigned_trade TEXT,            -- 分配的工种
    PRIMARY KEY (process, floor),
    FOREIGN KEY (process, floor) REFERENCES space(process, floor),
    FOREIGN KEY (assigned_trade) REFERENCES trade_resource(trade)
);

-- 3. 初始化工种资源
INSERT INTO trade_resource (trade)
SELECT DISTINCT trade 
FROM process;

-- 4. 初始化任务进度
INSERT INTO task_progress (process, floor, remaining_quantity, assigned_trade)
SELECT s.process, s.floor, s.quantity, p.trade
FROM space s
JOIN process p ON s.process = p.process;

-- 5. 创建项目状态视图
CREATE OR REPLACE VIEW current_project_status AS
SELECT 
    tp.floor,
    tp.process,
    p.trade,
    tp.remaining_quantity,
    tp.status,
    tr.status as trade_status,
    tp.start_day,
    tp.last_update_day
FROM task_progress tp
JOIN process p ON tp.process = p.process
JOIN trade_resource tr ON tp.assigned_trade = tr.trade
ORDER BY tp.floor, tp.process;
```
:::

::: {.cell .markdown}
# 第五部分：创建进度计算函数
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 第五部分：创建进度计算函数
---------------------------
-- 1. 任务执行函数：负责开始新的可执行任务
CREATE OR REPLACE FUNCTION update_task_progress(current_day INT)
RETURNS void AS $$
DECLARE
    task_record RECORD;
    assigned_trades TEXT[];  -- 用于跟踪已分配的工种
BEGIN
    -- 初始化已分配工种数组
    assigned_trades := ARRAY[]::TEXT[];

    -- 查找可以开始的任务（考虑依赖关系和工种可用性）
    FOR task_record IN (
        WITH available_tasks AS (
            SELECT tp.process, tp.floor, tp.assigned_trade
            FROM task_progress tp
            JOIN trade_resource tr ON tp.assigned_trade = tr.trade
            WHERE tp.status = 'pending'
            AND tr.status = 'available'
            AND NOT EXISTS (
                -- 检查依赖任务是否完成
                SELECT 1 FROM dependency d
                JOIN task_progress tp2 ON d.predecessor_process = tp2.process
                WHERE d.successor_process = tp.process
                AND tp2.status != 'completed'
                AND tp2.floor = tp.floor
            )
            ORDER BY tp.floor, tp.process  -- 优先处理低楼层任务
        )
        SELECT * FROM available_tasks
    )
    LOOP
        -- 检查工种是否已经被分配
        IF NOT task_record.assigned_trade = ANY(assigned_trades) THEN
            -- 更新任务状态为进行中
            UPDATE task_progress
            SET status = 'in_progress',
                start_day = current_day,
                last_update_day = current_day
            WHERE process = task_record.process
            AND floor = task_record.floor;

            -- 更新工种状态为忙碌
            UPDATE trade_resource
            SET status = 'busy'
            WHERE trade = task_record.assigned_trade;

            -- 将工种添加到已分配工种数组中
            assigned_trades := array_append(assigned_trades, task_record.assigned_trade);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 2. 每日进度更新函数：处理进行中的任务进度
CREATE OR REPLACE FUNCTION process_work_day(current_day INT)
RETURNS void AS $$
DECLARE
    task_record RECORD;
    work_done FLOAT;
BEGIN
    -- 处理所有进行中的任务
    FOR task_record IN (
        SELECT tp.*, p.initial_production_rate
        FROM task_progress tp
        JOIN process p ON tp.process = p.process
        WHERE tp.status = 'in_progress'
    )
    LOOP
        work_done := task_record.initial_production_rate;
        
        -- 更新剩余工作量和状态
        UPDATE task_progress
        SET remaining_quantity = GREATEST(0, remaining_quantity - work_done),
            last_update_day = current_day,
            status = CASE 
                WHEN remaining_quantity - work_done <= 0 THEN 'completed'
                ELSE 'in_progress'
            END
        WHERE process = task_record.process
        AND floor = task_record.floor;

        -- 如果任务完成，释放工种资源
        IF task_record.remaining_quantity - work_done <= 0 THEN
            UPDATE trade_resource
            SET status = 'available'
            WHERE trade = task_record.assigned_trade;
        END IF;
    END LOOP;
    
    -- 查找并开始新的可执行任务
    PERFORM update_task_progress(current_day);
END;
$$ LANGUAGE plpgsql;
```
:::

::: {.cell .markdown}
# 第六部分：创建日常工作记录表
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
DROP TABLE public.daily_work_history cascade;

-- 创建日常工作记录表
CREATE TABLE daily_work_history (
    day_number INTEGER,
    floor INTEGER,
    process VARCHAR(50),
    trade VARCHAR(50),
    remaining_quantity NUMERIC,
    productivity NUMERIC,
    task_status VARCHAR(20),
    trade_status VARCHAR(20),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (day_number, floor, process)
);
```
:::

::: {.cell .markdown}
# 第七部分：循环执行模拟
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
DO $$
DECLARE
    current_day INTEGER := 0;
    task_rec RECORD;
BEGIN
    -- 清空历史记录表（如果需要重新运行）
    TRUNCATE TABLE daily_work_history;
    
    LOOP
        -- 执行当天的工作并记录状态到历史表
        INSERT INTO daily_work_history (
            day_number, floor, process, trade, 
            remaining_quantity, productivity, task_status, trade_status
        )
        SELECT 
            current_day,
            tp.floor,
            tp.process,
            p.trade,
            tp.remaining_quantity,
            p.initial_production_rate,
            tp.status,
            tr.status
        FROM task_progress tp
        JOIN process p ON tp.process = p.process
        JOIN trade_resource tr ON tp.assigned_trade = tr.trade;

        -- 执行当天的工作
        PERFORM process_work_day(current_day);
        
        -- 输出当天的任务状态
        RAISE NOTICE '========== Day % ==========', current_day;
        FOR task_rec IN 
            SELECT 
                tp.floor,
                tp.process,
                p.trade,
                tp.remaining_quantity AS remaining,
                p.initial_production_rate AS productivity,
                tp.status AS task_status,
                tr.status AS trade_status
            FROM task_progress tp
            JOIN process p ON tp.process = p.process
            JOIN trade_resource tr ON tp.assigned_trade = tr.trade
            ORDER BY tp.floor, tp.process
        LOOP
            RAISE NOTICE 'Floor % - %: Trade=%, Remaining=%, Productivity=%/day, Status=%, Trade_Status=%',
                task_rec.floor,
                task_rec.process,
                task_rec.trade,
                task_rec.remaining,
                task_rec.productivity,
                task_rec.task_status,
                task_rec.trade_status;
        END LOOP;
        
        -- 检查是否所有任务完成
        EXIT WHEN NOT EXISTS (SELECT 1 FROM task_progress WHERE status != 'completed');
        
        current_day := current_day + 1;
    END LOOP;
    
    RAISE NOTICE '所有任务已完成！总天数：%', current_day + 1;
END $$;
```
:::

::: {.cell .markdown}
# 第八部分：查询
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 查询某一天的工作情况
SELECT 
    floor,
    process,
    trade,
    remaining_quantity,
    productivity,
    task_status,
    trade_status
FROM daily_work_history
WHERE day_number = 10  -- 这里可以修改要查询的天数
ORDER BY floor, process;
```
:::

::: {.cell .code vscode="{\"languageId\":\"sql\"}"}
``` sql
-- 全部计算最终结果输出
SELECT * FROM current_project_status;
```
:::
