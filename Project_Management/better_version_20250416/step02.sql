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
    initial_quantity INT NOT NULL CHECK (initial_quantity > 0),  -- 扰动后的初始任务量
    og_initial_quantity INT NOT NULL CHECK (og_initial_quantity > 0)  -- 原始任务量
);

-- 空间表：每个楼层的工作量与任务量相同
CREATE TABLE space (
    process TEXT REFERENCES task(process),  -- 工序名称（外键）
    floor INT CHECK (floor BETWEEN 1 AND 5),  -- 楼层（1-5）
    quantity INT NOT NULL,                   -- 该楼层的工作量（=任务初始量）
    PRIMARY KEY (process, floor)             -- 复合主键
);