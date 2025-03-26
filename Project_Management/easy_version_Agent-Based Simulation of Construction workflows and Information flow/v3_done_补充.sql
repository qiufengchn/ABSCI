-- 这一步是为了增加一列实际工作值用的，因为之前的数据表里没有这个字段，所以需要重新建立一个数据表，然后把之前的数据导入进去，可以是一个固定的值，也可以做一些模拟的数据，但是无论如何，这一天这个人做的事情都是白干，所以无所谓。

Drop Table daily_task_drawing cascade;

CREATE TABLE daily_task_drawing (
    day_number INT,
    process TEXT,
    floor INT,
    trade TEXT,
    is_invalid BOOLEAN,
    is_rework BOOLEAN,
    daily_work_done INT,
    efficiency TEXT,
    start_day INT,
    complete_day INT,
    work_efficiency NUMERIC(10, 2),  -- 100% work efficiency
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (day_number, process, floor)
);

-- Insert data from daily_task_record and calculate work_efficiency
INSERT INTO daily_task_drawing (day_number, process, floor, trade, is_invalid, is_rework, daily_work_done, efficiency, start_day, complete_day, work_efficiency)
SELECT 
    d.day_number,
    d.process,
    d.floor,
    d.trade,
    d.is_invalid,
    d.is_rework,
    d.daily_work_done,
    d.efficiency,
    d.start_day,
    d.complete_day,
    (p.initial_production_rate * tr.available_workers) AS work_efficiency
FROM daily_task_record d
JOIN process p ON d.process = p.process
JOIN trade_resource tr ON d.trade = tr.trade;

SELECT * FROM daily_task_drawing;