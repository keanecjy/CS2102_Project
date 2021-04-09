-- Routine 6 : add employees and create new course area when needed
call add_employee('Manager', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 1, 'Manager', 'Test1', 'Test2');
-- 2 rows
select area_name from course_areas where area_name in ('Test1', 'Test2');
call add_employee('Administrator', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 1, 'Administrator');
call add_employee('PT_Instructor', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 1, 'Part-time instructor', 'Test1', 'Test2');
call add_employee('FT_Instructor', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 1, 'Full-time instructor', 'Test1', 'Test2');
-- 4 rows
select * from employees where join_date = '04/08/2021'::date - 1;
call remove_employee(48, '04/08/2021'::date + 6);

call add_employee('Manager2', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 1, 'Manager');
call remove_employee(51, '2021-12-12');
-- insert into course_areas (area_name, eid) VALUES ('Testing', 51); -- error

-- Routine 5: add course
call add_course('Temp Course', 'Test', 'Test1', 1);
-- select * from courses where title = 'Temp Course';

-- Routine 10: add course offering (admin still can work as his depart_date after offering deadline)
call add_course_offering(17, '04/08/2021'::date, 1010, '04/08/2021'::date + 5, 1750, 48,
                         Array [[('04/08/2021'::date + 15)::text, '14:00', '1'], [('04/08/2021'::date + 15)::text, '15:00', '2'],
                                [('04/08/2021'::date + 15)::text, '16:00', '1'], [('04/08/2021'::date + 15)::text, '17:00', '1'],
                                [('04/08/2021'::date + 19)::text, '09:00', '2']]);

-- 5 rows
select * from sessions where course_id = 17;

-- note: target_num = seat_cap
select * from offerings where course_id = 17;
call remove_session(17, '04/08/2021', 5);
-- note: target_num > seat_cap
select * from offerings where course_id = 17;

-- 4 rows
select * from sessions where course_id = 17;

-- Routine 2: remove employee
call add_employee('ToDelete', 'Tester', 999, 'Test@email.com', 9.99, '04/08/2021'::date - 10, 'Administrator');
call remove_employee(52, '04/08/2021'::date);
call remove_employee(50, '2021-04-26');
call remove_employee(49, '04/08/2021'::date + 10); -- update fail w warning message (no exception)
-- 2 rows
select * from employees where address = 'Tester' and depart_date is not null;

-- Routine 3: add customer
call add_customer('Cust1', 'Tester', 999, 'Test@email.com', '0000000000000000', '04/08/2021'::date + 365, '000');
call add_customer('Cust2', 'Tester', 999, 'Test@email.com', '1111111111111111', '04/08/2021'::date + 365, '111');
-- 2 rows
select * from customers where address = 'Tester';


-- Routine 4: update credit card
call update_credit_card(41, '4141414141414141', '04/08/2021'::date + (365 * 2), '414');
call update_credit_card(42, '4242424242424242', '04/08/2021'::date + (365 * 2), '424');
-- reactivate old card
call update_credit_card(41, '0000000000000000', '04/08/2021'::date + (365), '000');
--4 rows
select cc.* from customers natural join credit_cards cc where address = 'Tester';


-- Routine 6: find instructors
-- 0 rows
select * from find_instructors(17, '04/08/2021'::date + 15, '14:00');
-- 2 row
select * from find_instructors(17, '04/08/2021'::date + 12, '14:00');
-- 1 row (instructor left, full time fired)
select * from find_instructors(17, '04/08/2021'::date + 20, '14:00');


-- Routine 7: get available instructors
call add_course_offering(17, '04/08/2021'::date - 1, 10, '04/08/2021'::date + 5, 100, 48,
                         Array [['04/27/2021', '9:00', '5']]);
-- 4 rows
select * from employees where address = 'Tester' and depart_date is not null;

select * from get_available_instructors(17, '04/08/2021'::date + 10, '04/08/2021'::date + 20);

-- Routine 24: add session
call add_session(17, '04/08/2021'::date - 1, 10, '2021-04-26', '17:00', 49, 10);
-- 5 rows
select * from sessions where course_id = 17;

-- Routine 8: find rooms
select * from find_rooms('2021-04-26', '17:00', 1);

-- Routine 22: update room
call update_room(17, '04/08/2021'::date - 1, 10, 1);

-- Routine 21: update instructor
select * from find_instructors(17, '2021-04-26', '17:00');
call update_instructor(17, '04/08/2021'::date - 1, 10, 50);

-- Routine 9: get avail rooms
select * from get_available_rooms('04/08/2021'::date + 10, '04/08/2021'::date + 20);

-- Routine 23: remove session
call remove_session(17, '04/08/2021'::date - 1, 10);

-- Routine 11: add course packages
call add_course_package('Test Package', 1, '04/08/2021'::date, '04/08/2021'::date + 50, 100.25);

-- Routine 12: get avail course packages
select * from get_available_course_packages();

-- Routine 13: buy course packages
call buy_course_package(41, 41);
call buy_course_package(42, 41);
-- call buy_course_package(50, 41); -- cid does not exist
-- call buy_course_package(41, 50); -- pid does not exist

--2 rows
select * from buys where package_id = 41;

-- Routine 15: get available course offerings
select * from get_available_course_offerings();

-- Routine 16: get available course sessions
select * from get_available_course_sessions(17, '04/08/2021');

-- Routine 17: register session
call register_session(41, 17, '04/08/2021', 1, 'card');
call register_session(42, 17, '04/08/2021'::date - 1, 1, 'card');

call register_session(41, 17, '04/08/2021'::date - 1, 1, 'redeem');
call register_session(42, 17, '04/08/2021', 3, 'redeem');

-- Routine 14: get my course package
select jsonb_pretty(get_my_course_package::jsonb) from get_my_course_package(8);
select jsonb_pretty(get_my_course_package::jsonb) from get_my_course_package(41);
select jsonb_pretty(get_my_course_package::jsonb) from get_my_course_package(42);
-- call buy_course_package(41, 39); --cannot buy bcos got partially active package

-- Routine 18: get my registration
select * from get_my_registrations(8);
select * from get_my_registrations(41);
select * from get_my_registrations(42);

-- Routine 20: cancel registration
call cancel_registration(41, 17, '04/08/2021'::date);
select * from get_my_registrations(41);
call register_session(41, 17, '04/08/2021'::date, 2, 'card');
select * from get_my_registrations(41);

-- Routine 19: update course session
call update_course_session(41, 17, '04/08/2021'::date, 4);
select * from get_my_registrations(41);

-- Routine 25: pay salary
select * from pay_salary();

-- Routine 26: promote courses
select * from get_available_course_offerings();
select * from promote_courses();
-- filtered promote courses
select * from promote_courses() where cust_id in (16, 27);

-- Routine 27: top packages
-- 2 rows
select * from top_packages(1);
-- 2 rows
select * from top_packages(2);
-- 6 rows
select * from top_packages(6);
-- 29 rows
select * from top_packages(7);

-- Routine 28: popular courses
call cancel_registration(41, 17, '2021-04-08');
-- 1 row
select * from popular_courses();

-- Routine 29: view_summary report
select * from view_summary_report(10);

-- Routine 30: view manager report
-- Manager 18 (Caspar Singyard) was fired last year and not in current year report
select * from view_manager_report();