/*==================================================================
 步骤3：插入基础数据（所有数值保持整数） - 基于 data.md 更新
==================================================================*/
-- 插入工序数据（工序名称、工种、初始生产率） - 来自 data.md 表1
INSERT INTO process (process, trade, initial_production_rate) VALUES
('Electric conduits in the floor', 'Electricity', 51),
('Electric conduits in the wall',  'Electricity', 41),
('Floor tiling',                   'Tiling',      62),
('Gravel base layer',              'Gravel',      34),
('Partition phase 1',              'Partition',   55),
('Partition phase 2',              'Partition',   51),
('Partition phase 3',              'Partition',   32),
('Pipes in the floor',             'Plumbing',    69),
('Pipes in the wall',              'Plumbing',    37),
('Wall tiling',                    'Tiling',      27);

-- 插入带扰动的任务数据：基于 data.md 表3 的 InitialQuantity 作为原始数据 (og_initial_quantity)
-- initial_quantity 仍然使用 ±10% 随机扰动并取整
INSERT INTO task (process, initial_quantity, og_initial_quantity) VALUES
    ('Gravel base layer',              ROUND(170 * (0.9 + 0.2 * random()))::INT, 170),
    ('Pipes in the floor',             ROUND(100 * (0.9 + 0.2 * random()))::INT, 100),
    ('Electric conduits in the floor', ROUND(80  * (0.9 + 0.2 * random()))::INT, 80),
    ('Floor tiling',                   ROUND(720 * (0.9 + 0.2 * random()))::INT, 720),
    ('Partition phase 1',              ROUND(750 * (0.9 + 0.2 * random()))::INT, 750),
    ('Pipes in the wall',              ROUND(190 * (0.9 + 0.2 * random()))::INT, 190),
    ('Electric conduits in the wall',  ROUND(180 * (0.9 + 0.2 * random()))::INT, 180),
    ('Partition phase 2',              ROUND(20  * (0.9 + 0.2 * random()))::INT, 20),
    ('Wall tiling',                    ROUND(290 * (0.9 + 0.2 * random()))::INT, 290),
    ('Partition phase 3',              ROUND(200 * (0.9 + 0.2 * random()))::INT, 200);


-- 插入依赖关系：定义工序执行顺序约束 - 来自 data.md 表2
INSERT INTO dependency (predecessor_process, successor_process) VALUES
('Gravel base layer',              'Pipes in the floor'),
('Gravel base layer',              'Electric conduits in the floor'),
('Pipes in the floor',             'Floor tiling'),
('Electric conduits in the floor', 'Floor tiling'),
('Partition phase 1',              'Pipes in the wall'),
('Pipes in the wall',              'Partition phase 2'),
('Partition phase 2',              'Electric conduits in the wall'),
('Electric conduits in the wall',  'Partition phase 3'),
('Partition phase 3',              'Wall tiling');

-- 生成空间数据：每个工序分配到1-5层，工作量=扰动后的任务初始量 (initial_quantity)
-- 注意：这里使用 task 表中扰动后的 initial_quantity 分配到每个楼层
INSERT INTO space (process, floor, quantity)
SELECT
    t.process,
    f.floor,
    t.initial_quantity -- 使用扰动后的初始量作为每层的工作量基础
FROM task t
CROSS JOIN generate_series(1, 5) AS f(floor);

-- -- 以下 UPDATE 语句会覆盖上面基于 data.md 插入的特定值，
-- -- 如果希望保留 data.md 的初始生产率和扰动后的初始工程量，应注释掉或删除它们。
-- -- 更新任务表，每个工作任务的工作量为为=ROUNDDOWN(RAND()*400,0)
-- -- 更新 task 表中的 initial_quantity 为随机值（0 到 399 的整数）
-- UPDATE task
-- SET initial_quantity = FLOOR(random() * 400)::INT;

-- -- 更新process表中的 initial_production_rate 为随机值（1 到 100 的整数）
-- UPDATE process
-- SET initial_production_rate = FLOOR(1 + random() * 100)::INT;

-- ... 后续步骤的代码 ...