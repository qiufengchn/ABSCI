
# 修改代码过程

为了根据任务剩余工作量动态停止模拟，并逐日显示详细信息，以下是修改后的步骤和代码：

### 修改说明：
1. **循环条件调整**：将固定30天改为检查所有任务是否完成。
2. **每日详细输出**：在循环中遍历任务状态，显示工种、剩余量、生产率等信息。
3. **天数计算优化**：确保天数准确反映实际处理天数。

### 修改后的模拟代码（替换原第六部分）：
```sql
-- 第六部分：执行模拟
-------------------
DO $$
DECLARE
    current_day INTEGER := 0;
    task_rec RECORD;
BEGIN
    LOOP
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

### 关键改动解析：
1. **动态终止条件**：
   ```sql
   EXIT WHEN NOT EXISTS (SELECT 1 FROM task_progress WHERE status != 'completed');
   ```
   当所有任务状态为 `completed` 时终止循环。

2. **详细日志输出**：
   - 使用 `RAISE NOTICE` 输出每个任务的：
     - 楼层 (`floor`)
     - 工序名称 (`process`)
     - 工种 (`trade`)
     - 剩余工作量 (`remaining`)
     - 初始生产率 (`productivity`)
     - 任务状态 (`task_status`)
     - 工种状态 (`trade_status`)

3. **天数计算**：
   - 最后输出的总天数为 `current_day + 1`，因为循环从第0天开始计数。

### 示例输出片段：
```sql
NOTICE:  ========== Day 0 ==========
NOTICE:  Floor 1 - Gravel base layer: Trade=Gravel, Remaining=170, Productivity=34/day, Status=in_progress, Trade_Status=busy
NOTICE:  Floor 1 - Pipes in the floor: Trade=Plumbing, Remaining=100, Productivity=69/day, Status=pending, Trade_Status=available
...
NOTICE:  ========== Day 1 ==========
NOTICE:  Floor 1 - Gravel base layer: Trade=Gravel, Remaining=136, Productivity=34/day, Status=in_progress, Trade_Status=busy
...
NOTICE:  所有任务已完成！总天数：15
```

### 结果解读：
- **逐日信息**：每天列出所有任务的实时状态，包括剩余工作量、工种忙碌情况等。
- **效率优化**：任务按依赖关系和工种可用性动态推进，直到所有任务完成。
- **准确停止**：无需预设天数，完全依赖任务进度自动终止。

此修改确保了模拟的真实性和结果的完整性，同时提供透明的每日进展跟踪。


---

可以通过以下步骤查询最终计算结果，包括任务完成状态、工种资源情况及详细的任务执行记录：

---

### **1. 查看项目总体状态**
使用预定义的 `current_project_status` 视图，展示每个任务在各楼层的实时进度、工种状态及时间信息：
```sql
SELECT * FROM current_project_status;
```
**输出示例**：
```
floor | process                     | trade      | remaining_quantity | status     | trade_status | start_day | last_update_day
------|-----------------------------|------------|--------------------|------------|--------------|-----------|-----------------
1     | Gravel base layer           | Gravel     | 0                  | completed  | available    | 0         | 4
1     | Pipes in the floor          | Plumbing   | 0                  | completed  | available    | 5         | 8
...  (其他楼层和任务数据)
```

---

### **2. 查看工种资源状态**
直接查询 `trade_resource` 表，确认每个工种的当前可用性：
```sql
SELECT * FROM trade_resource;
```
**输出示例**：
```
trade       | available_workers | status
------------|-------------------|---------
Electricity | 1                 | available
Plumbing    | 1                 | available
Tiling      | 1                 | available
... 
```

---

### **3. 查看任务完成顺序**
按任务开始时间排序，列出所有非待处理任务的执行顺序：
```sql
SELECT 
    floor, 
    process, 
    start_day AS "开始天数", 
    last_update_day AS "完成天数", 
    status AS "任务状态"
FROM task_progress
WHERE status != 'pending'
ORDER BY start_day;
```
**输出示例**：
```
floor | process                     | 开始天数 | 完成天数 | 任务状态
------|-----------------------------|---------|---------|----------
1     | Gravel base layer           | 0       | 4       | completed
1     | Pipes in the floor          | 5       | 8       | completed
1     | Floor tiling                | 9       | 21      | completed
...
```

---

### **4. 生成详细任务报告**
结合 `task_progress` 和 `process` 表，显示每个任务的生产率、总工作量及完成天数：
```sql
SELECT 
    tp.floor,
    tp.process,
    p.trade,
    (s.quantity - tp.remaining_quantity) AS "已完成量",
    s.quantity AS "总工作量",
    p.initial_production_rate AS "生产率/天",
    (tp.last_update_day - tp.start_day + 1) AS "耗时天数"
FROM task_progress tp
JOIN process p ON tp.process = p.process
JOIN space s ON tp.process = s.process AND tp.floor = s.floor
WHERE tp.status = 'completed'
ORDER BY tp.floor, tp.start_day;
```
**输出示例**：
```
floor | process                     | trade      | 已完成量 | 总工作量 | 生产率/天 | 耗时天数
------|-----------------------------|------------|---------|---------|-----------|---------
1     | Gravel base layer           | Gravel     | 170     | 170     | 34        | 5
1     | Pipes in the floor          | Plumbing   | 100     | 100     | 69        | 2
...
```

---

### **5. 验证所有任务是否完成**
确认所有任务的剩余工作量为零且状态为 `completed`：
```sql
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM task_progress WHERE status != 'completed') 
        THEN '仍有任务未完成' 
        ELSE '所有任务已完成' 
    END AS completion_check;
```
**输出示例**：
```
completion_check
-----------------
所有任务已完成
```

---

### **6. 查看模拟日志中的逐日记录**
模拟过程中的每日详细日志已通过 `RAISE NOTICE` 输出到控制台，格式如下：
```
NOTICE:  ========== Day 0 ==========
NOTICE:  Floor 1 - Gravel base layer: Trade=Gravel, Remaining=170, Productivity=34/day, Status=in_progress, Trade_Status=busy
NOTICE:  Floor 1 - Pipes in the floor: Trade=Plumbing, Remaining=100, Productivity=69/day, Status=pending, Trade_Status=available
...
```

---

### **总结**
通过上述查询，可以全面获取以下信息：
1. **任务完成状态**：各楼层任务的开始、完成时间及剩余量。
2. **资源分配情况**：工种是否空闲或忙碌。
3. **生产效率分析**：任务的实际耗时与理论生产率对比。
4. **动态终止验证**：确保模拟在任务全部完成后停止。

---

我想查看每天的内容，但是同时每天显示的又是截至到当天，全部工作的情况，包含完成已完成量，总工作量，trade是什么，trade是否空闲（有几人工作），当前的工作的任务状态是什么，开始的天数和结束的天数等等详细信息。
