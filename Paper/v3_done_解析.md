
## 基本介绍

---
## 步骤1：清理环境（每次重新运行前必须执行）

```sql
/*==================================================================
 步骤1：清理环境（每次重新运行前必须执行）
==================================================================*/
-- 删除所有相关表和视图，CASCADE 确保级联删除依赖对象
DROP TABLE IF EXISTS daily_task_record, daily_work_history, task_progress, trade_resource, space, task, dependency, process CASCADE;

DROP VIEW IF EXISTS current_project_status, project_progress_details CASCADE;
```


---

## 步骤2：创建基础表结构（所有数值字段使用整数）

```sql
/*==================================================================
 步骤2：创建基础表结构（所有数值字段使用整数）
==================================================================*/
-- 工序表：核心基准数据，记录工序名称、工种和初始生产率
CREATE TABLE process (
    process TEXT PRIMARY KEY,              -- 工序名称（主键）
    trade TEXT NOT NULL,                   -- 所属工种（如 Plumbing、Electricity）
    initial_production_rate INT NOT NULL CHECK (initial_production_rate > 0)  -- 初始生产率（单位：工作量/人/天）
);

-- 依赖关系表：记录工序间的依赖关系（前置工序 -> 后续工序）
CREATE TABLE dependency (
    predecessor_process TEXT REFERENCES process(process),  -- 前置工序
    successor_process TEXT REFERENCES process(process),    -- 后续工序
    PRIMARY KEY (predecessor_process, successor_process)   -- 复合主键
);

-- 任务表：带±10%随机扰动的初始任务量（结果取整）
CREATE TABLE task (
    process TEXT PRIMARY KEY REFERENCES process(process),  -- 工序名称（外键）
    initial_quantity INT NOT NULL CHECK (initial_quantity > 0)  -- 扰动后的初始任务量
);

-- 空间表：每个楼层的工作量与任务量相同
CREATE TABLE space (
    process TEXT REFERENCES task(process),  -- 工序名称（外键）
    floor INT CHECK (floor BETWEEN 1 AND 5),  -- 楼层（1-5）
    quantity INT NOT NULL,                   -- 该楼层的工作量（=任务初始量）
    PRIMARY KEY (process, floor)             -- 复合主键
);
```

## 步骤3：插入基础数据（所有数值保持整数）

```sql
/*==================================================================
 步骤3：插入基础数据（所有数值保持整数）
==================================================================*/
-- 插入工序数据（工序名称、工种、初始生产率）
INSERT INTO process VALUES
('Gravel base layer',          'Gravel',    34),  -- 碎石基层
('Pipes in the floor',         'Plumbing',  69),  -- 地板管道
('Electric conduits in the floor', 'Electricity', 51),  -- 地板电缆管道
('Floor tiling',               'Tiling',    62),  -- 地板铺砖
('Partition phase 1',          'Partition', 55),  -- 隔断阶段1
('Pipes in the wall',          'Plumbing',  37),  -- 墙面管道
('Partition phase 2',          'Partition', 51),  -- 隔断阶段2
('Electric conduits in the wall', 'Electricity', 41),  -- 墙面电缆管道
('Partition phase 3',          'Partition', 32),  -- 隔断阶段3
('Wall tiling',                'Tiling',    27);  -- 墙面铺砖

-- 插入带扰动的任务数据：基于原始数据 ±10% 随机扰动并取整
INSERT INTO task 
SELECT 
    process, 
    ROUND(initial_quantity * (0.9 + 0.2 * random()))::INT  -- 扰动公式
FROM (VALUES  -- 原始数据
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

-- 插入依赖关系：定义工序执行顺序约束
INSERT INTO dependency VALUES
('Gravel base layer', 'Pipes in the floor'),          -- 碎石基层完成才能开始地板管道
('Gravel base layer', 'Electric conduits in the floor'),
('Pipes in the floor', 'Floor tiling'),              -- 地板管道完成才能开始铺砖
('Electric conduits in the floor', 'Floor tiling'),
('Partition phase 1', 'Pipes in the wall'),           -- 隔断阶段1完成才能开始墙面管道
('Pipes in the wall', 'Partition phase 2'),
('Partition phase 2', 'Electric conduits in the wall'),
('Electric conduits in the wall', 'Partition phase 3'),
('Partition phase 3', 'Wall tiling');

-- 生成空间数据：每个工序分配到1-5层，工作量=任务总量
INSERT INTO space 
SELECT 
    t.process, 
    f.floor, 
    t.initial_quantity
FROM task t
CROSS JOIN generate_series(1, 5) AS f(floor);  -- 使用交叉连接生成5层数据
```

## 步骤4：创建资源与任务进度跟踪表

```sql
/*==================================================================
 步骤4：创建资源与任务进度跟踪表
==================================================================*/
-- 工种资源表：记录各工种可用工人数和状态
CREATE TABLE trade_resource (
    trade TEXT PRIMARY KEY,                     -- 工种名称
    available_workers INT DEFAULT 1 CHECK (available_workers >= 1),  -- 可用工人数（默认1）
    status TEXT DEFAULT 'available' CHECK (status IN ('available','busy'))  -- 资源状态
);

-- 任务进度表：跟踪每个工序在各楼层的进度
CREATE TABLE task_progress (
    process TEXT REFERENCES process(process),   -- 工序名称
    floor INT,                                  -- 楼层
    remaining_quantity INT CHECK (remaining_quantity >= 0),  -- 剩余工作量
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending','in_progress','completed')),  -- 任务状态
    start_day INT,                              -- 任务开始日
    last_update_day INT,                        -- 最后更新日
    assigned_trade TEXT REFERENCES trade_resource(trade),  -- 分配的工种
    planned_remaining INT,                      -- 初始计划剩余量
    daily_productivity INT,                      -- 实际日效率
    PRIMARY KEY (process, floor)                 -- 复合主键
);

-- 初始化工种资源：插入所有工种，默认可用工人数为1
INSERT INTO trade_resource (trade) VALUES 
('Gravel'), ('Plumbing'), ('Electricity'), ('Tiling'), ('Partition');

-- 初始化任务进度：为每个工序的每个楼层创建初始记录
INSERT INTO task_progress (
    process, floor, remaining_quantity, 
    assigned_trade, planned_remaining
)
SELECT 
    s.process, 
    s.floor, 
    s.quantity,       -- 初始剩余量=总工作量
    p.trade,          -- 从工序表获取工种
    s.quantity        -- 初始计划剩余量
FROM space s
JOIN process p USING (process);
```

## 步骤5：创建更新任务进度的函数（增加楼层先后顺序判断）

```sql
/*==================================================================
 步骤5：创建更新任务进度的函数（增加楼层先后顺序判断）
==================================================================*/
-- 函数功能：启动符合条件的新任务（依赖完成、低楼层完成、工种可用）
CREATE OR REPLACE FUNCTION update_task_progress(current_day INT)
RETURNS void AS $$
DECLARE
    task_record RECORD;
    assigned_trades TEXT[] := ARRAY[]::TEXT[];  -- 记录已分配工种，避免重复占用
BEGIN
    -- 查询符合条件的待启动任务（按楼层和工序排序）
    FOR task_record IN (
        SELECT 
            tp.process,
            tp.floor,
            tp.assigned_trade
        FROM task_progress tp
        WHERE tp.status = 'pending'
          -- 检查依赖是否完成（同一楼层）
          AND NOT EXISTS (
              SELECT 1 
              FROM dependency d
              JOIN task_progress tp2 ON d.predecessor_process = tp2.process
              WHERE d.successor_process = tp.process
                AND tp2.floor = tp.floor 
                AND tp2.status != 'completed'
          )
          -- 检查低楼层是否完成（同一工序）
          AND NOT EXISTS (
              SELECT 1
              FROM task_progress lower_tp 
              WHERE lower_tp.process = tp.process
                AND lower_tp.floor < tp.floor
                AND lower_tp.status != 'completed'
          )
          -- 检查工种是否可用
          AND EXISTS (
              SELECT 1 
              FROM trade_resource tr
              WHERE tr.trade = tp.assigned_trade
                AND tr.status = 'available'
          )
        ORDER BY tp.floor, tp.process  -- 按楼层和工序顺序启动
    )
    LOOP
        -- 确保同一工种不同时分配多个任务
        IF NOT task_record.assigned_trade = ANY(assigned_trades) THEN
            -- 更新任务状态为进行中，记录开始时间
            UPDATE task_progress
            SET 
                status = 'in_progress',
                start_day = current_day,
                last_update_day = current_day
            WHERE process = task_record.process
              AND floor = task_record.floor;

            -- 标记工种为忙碌状态
            UPDATE trade_resource
            SET status = 'busy'
            WHERE trade = task_record.assigned_trade;

            assigned_trades := array_append(assigned_trades, task_record.assigned_trade);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## 步骤6：创建每日记录表


```sql
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
```

##  步骤7：扩展处理每日工作的函数（记录每日详细信息）

```sql
/*==================================================================
 步骤7：扩展处理每日工作的函数（记录每日详细信息）
==================================================================*/
CREATE OR REPLACE FUNCTION process_work_day(current_day INT)
RETURNS void AS $$
DECLARE
    task_rec RECORD;
    work_done INT;          -- 当日实际完成量
    is_invalid BOOLEAN;     -- 是否无效日
    new_remaining INT;      -- 更新后剩余量
    eff NUMERIC(10,2);      -- 效率计算值
    is_rework BOOLEAN;      -- 是否返工
BEGIN
    -- 遍历所有进行中的任务
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
        -- 生成10%无效日概率
        is_invalid := (random() < 0.1);
      
        -- 计算实际完成量：无效日为0，否则应用扰动公式
        work_done := CASE 
            WHEN is_invalid THEN 0
            ELSE GREATEST(1, ROUND(task_rec.initial_production_rate * (0.9 + 0.2 * random())) * task_rec.available_workers)
        END;
      
        -- 更新剩余工作量
        new_remaining := CASE 
            WHEN task_rec.remaining_quantity <= work_done THEN 0 
            ELSE task_rec.remaining_quantity - work_done 
        END;
      
        -- 更新任务进度表
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
      
        -- 任务完成时释放工种资源
        IF new_remaining = 0 THEN
            UPDATE trade_resource
            SET status = 'available'
            WHERE trade = task_rec.assigned_trade;
        END IF;
      
        -- 判断返工：任务启动日早于当前日
        is_rework := (task_rec.start_day IS NOT NULL AND task_rec.start_day < current_day);
      
        -- 计算效率百分比
        IF (task_rec.initial_production_rate * task_rec.available_workers) > 0 THEN
            eff := ROUND((work_done::NUMERIC / (task_rec.initial_production_rate * task_rec.available_workers)) * 100, 2);
        ELSE
            eff := 0;
        END IF;
      
        -- 插入每日详细记录
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
  
    -- 启动新任务
    PERFORM update_task_progress(current_day);
END;
$$ LANGUAGE plpgsql;
```

## 步骤8：执行模拟


```sql
/*==================================================================
 步骤8：执行模拟
==================================================================*/
-- 使用匿名代码块模拟每日工作，直到所有任务完成或达到365天
DO $$
DECLARE 
    current_day INTEGER := 0;
    max_days INTEGER := 365;  -- 最大模拟天数
BEGIN
    -- 清空历史记录表
    TRUNCATE TABLE daily_work_history;
    TRUNCATE TABLE daily_task_record;
  
    -- 按天循环处理
    WHILE current_day < max_days LOOP
        -- 记录当日状态到历史表
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
      
        -- 执行当日工作
        PERFORM process_work_day(current_day);
      
        -- 检查是否全部任务完成
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM task_progress WHERE status != 'completed'
        );
        current_day := current_day + 1;
    END LOOP;
  
    RAISE NOTICE 'Simulation completed in % days', current_day;  -- 输出模拟结果
END $$;
```

## 步骤9：查看结果

```sql
/*==================================================================
 步骤9：查看结果
==================================================================*/
-- 创建视图：汇总项目进度详情（含工种状态、累计完成量等）
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

-- 查询每日详细记录（按天、工序、楼层排序）
SELECT * FROM daily_task_record ORDER BY day_number, process, floor;
```

---

## 内容小结

