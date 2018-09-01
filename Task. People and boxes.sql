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

declare  @people table(bid int  primary key identity(1,1), qty int )
declare @box table(pid int  primary key identity(1,1), qty int )

Insert into @box 
Values
  (4),
  (5),
  (2),
  (9),
  (5)

Insert into @people
Values
  (2),
  (3),
  (9),
  (4),
  (8)

-- Expected query result:

pid, boxid, qty (взятое кол-во)
1,1,2
  2,1,2
  2,2,1
  3,2,4
  3,3,2,
  3,4,3
  4,4,4
  5,4,2
  5,5,5
*/

DECLARE @people TABLE(pid int primary key identity(1,1), qty int)
DECLARE @box TABLE (boxid int primary key identity(1,1), qty int)

INSERT INTO @box (qty)
VALUES
  (4),
  (5),
  (2),
  (9),
  (5)

INSERT INTO @people(qty)
VALUES
  (2),
  (3),
  (9),
  (4),
  (8)

------------------------------------------------------------------------------------------------------
-- solution:
------------------------------------------------------------------------------------------------------

;WITH boxes AS
(
	SELECT
		boxid,
		ISNULL(SUM(qty) OVER(ORDER BY boxid ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) as b_bef,
		SUM(qty) OVER(ORDER BY boxid ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as b_aft	
	FROM 
		@box b
),
people AS
(
	SELECT
		pid,	
		ISNULL(SUM(qty) OVER(ORDER BY pid ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) as p_bef,
		SUM(qty) OVER(ORDER BY pid ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as p_aft	
	FROM 
		@people p
)	
SELECT
	boxid,pid,
		CASE WHEN p_aft <= b_aft THEN p_aft ELSE b_aft END -
		CASE WHEN p_bef >= b_bef THEN p_bef ELSE b_bef END
	as [get]
FROM
	boxes b
	INNER JOIN people p ON
		b_aft between p_bef and p_aft
		OR
		p_aft between b_bef and b_aft


	
