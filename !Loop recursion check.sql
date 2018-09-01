/*
 Ниже решение для уже существующей таблицы с данными , где есть записи parent_id > id
 Иначе наиболее грамотным будет решение с ограничениями: CHECK (id >= 1), CHECK (parent_id < id)
 
 This solution for already existing table with data using in trigger, 
 otherwise the most correct solution will be adding Check constraint to parent id
*/

IF (NOT OBJECT_id('tempdb..#MyTable') IS NULL) 
	DROP TABLE #MyTable

CREATE TABLE #MyTable (
    id INT NOT NULL PRIMARY KEY,
    parent_id INT NULL
--	,CHECK (id >= 1)
--	,CHECK (parent_id < id)
);

--ALTER TABLE #MyTable ADD FOREIGN KEY (parent_id) REFERENCES MyTable(id);
CREATE INDEX #IX_MyTable_parent_id ON #MyTable (parent_id)


INSERT INTO #MyTable (id, parent_id ) 
VALUES
    (1, NULL),
    (2, 6),
    (3, 2),
    (4, 3),
    (5, 4)
    ,(6, 5)


;WITH rcte AS 
(
    --- Anchor: any row in #MyTable could be an anchor
    --- in an infinite recursion.
    SELECT 
		parent_id AS start_id,
        id,
        CAST(id AS varchar(MAX)) AS [path]
    FROM 
		#MyTable
    UNION ALL
    --- Find children. Keep this up until we circle back
    --- to the anchor row, which we keep in the "start_id"
    --- column.
    SELECT 
		rcte.start_id,
        t.id,
        CAST(CONCAT(rcte.[path],' -> ',t.id)  AS varchar(MAX)) AS [path]
    FROM
		rcte
		INNER JOIN #MyTable AS t ON
			t.parent_id=rcte.id
    WHERE 
		rcte.start_id!=rcte.id
)
SELECT TOP 100
	start_id,[path]
FROM 
	rcte
WHERE 
	start_id = id
ORDER BY
	id desc
OPTION (MAXRECURSION 0);    -- eliminates "assert" operator.

with recur as
(
	SELECT id,parent_id
	
	FROM
		#MyTable	
	union all
	SELECT m.id,m.parent_id
	FROM
		#MyTable m
		INNER JOIN recur c ON
			c.id = m.parent_id
	
)
SELECT
*
FROM
	recur