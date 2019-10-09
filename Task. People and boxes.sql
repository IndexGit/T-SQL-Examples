/*
ENG:

"People and boxes"
Having two tables "@box" and "@people"
Any box has quantity of some think "@box.qty"
Any people can take some qty of them "@people.qty"

You need write one query that returns result of qty taking process (bid,pid, get - taken count of thinks).
Constraints: 
 - one people in one time order by "@people.pid" take from one box order by "@box.bid".
 - It is not allowed to touch next box while current not empty.
 - Only one query
----------------------------------------------------------------------------------------
Русский:

Люди и коробки
Есть 2 таблицы: люди и коробки
В коробках по N штук карандашей, каждый человек может и должен взять M карандашей.

Написать один запрос (не цикл и не курсор) который выводит результат вытаскивания карандашей из коробок, 
каждая строка - одно взаимодействие человека с коробкой. 

Ограничения: 
  Заходят по одному, берут по очереди из коробок в ряд по pid и bid. 
  Т.е. пока коробка не пустая, следующую не трогают.
  Решение в виде одного запроса
----------------------------------------------------------------------------------------

-- Tables description:

DECLARE @people TABLE(pid int primary key identity(1,1), qty int)
DECLARE @box TABLE (boxid int primary key identity(1,1), qty int)

INSERT INTO @box (qty)
VALUES
  (4),
  (5),
  (2),
  (9),
  (15)

INSERT INTO @people(qty)
VALUES
  (2),
  (3),
  (9),
  (4),
  (1),
  (1),
  (2),
  (13),
  (2)

------------------------------------------------------------------------------------------------------
-- solution:
------------------------------------------------------------------------------------------------------

-- boxes
;WITH boxes AS
(
	SELECT
		boxid,
		ISNULL(SUM(qty) OVER(ORDER BY boxid ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) as b_bef,	-- count of total items before this box was opened
		SUM(qty) OVER(ORDER BY boxid ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as b_aft	,		-- count of total items after opening this box
		qty
	FROM 
		@box b
),
people AS
(
	SELECT
		pid,	
		ISNULL(SUM(qty) OVER(ORDER BY pid ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) as p_bef,	-- count of items was taken before this man
		SUM(qty) OVER(ORDER BY pid ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as p_aft,			-- count of items was taken with this man total
		qty
	FROM 
		@people p
)	
SELECT
	boxid,			-- id of current box
	pid,			-- id of current man
	b_bef,			-- count of total items before this box was opened
	b_aft,			-- count of total items after opening this box
	p_bef,			-- count of items was taken before this man
	p_aft,			-- count of items was taken with this man total
		CASE WHEN p_aft <= b_aft THEN p_aft ELSE b_aft END -
		CASE WHEN p_bef >= b_bef THEN p_bef ELSE b_bef END
	as [get],		-- count of items was taken from this [boxid] box by [pid] man
	p.qty as pqty,	-- count items can take current man
	b.qty as bqty	-- count of items in current box
FROM
	boxes b
	INNER JOIN people p ON
		b_aft BETWEEN p_bef AND p_aft
		OR
		p_aft BETWEEN b_bef AND b_aft
ORDER BY
	boxid,pid


