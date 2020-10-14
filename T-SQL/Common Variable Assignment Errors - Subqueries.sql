drop table if exists #Foo

create table #Foo
(
	Id int identity(1,1)
	, MyValue varchar(25) not null
	, Active bit not null
)
INSERT INTO #Foo
(
    MyValue
  , Active
)
values
(   'Bar'   -- MyValue - varchar(25)
  , 1 -- Active - bit
    ),
(   'Bar'   -- MyValue - varchar(25)
  , 0 -- Active - bit
    )

declare @MyID int
--Example 1: Assured that 1 and only 1 value ever exists
set @MyID = (select id from #Foo where Active = 1)
select @MyID

select @MyID = id from #Foo where Active = 1
select @MyID


--Example 2: Not assured that 1 and only 1 value ever exists
set @MyID = (select id from #Foo where MyValue = 'Bar')
/* OOPS, returns error:
Msg 512, Level 16, State 1, Line 32
Subquery returned more than 1 value. This is not permitted when the subquery follows =, !=, <, <= , >, >= or when the subquery is used as an expression.
*/
select @MyID

select @MyID = id from #Foo where MyValue = 'Bar'
/*
Doesn't return an error, but you can't be assured that the value is "correct". You would need a TOP/ORDER BY to assure the value
*/
select @MyID
