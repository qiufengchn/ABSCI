
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
