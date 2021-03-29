/*****************
 * User functions
 *****************/

/** 
 * add_course_pacakage(): used to add a new course package
 */ 
CREATE OR REPLACE FUNCTION add_course_package(name text, num_courses int, 
    start_date date, end_date date, price float)
RETURNS course_packages AS $$
DECLARE
    pid int;
    rec course_packages;
BEGIN
    select coalesce(max(package_id), 0) + 1 into pid
    from course_packages;

    insert into course_packages 
    values (pid, name, num_courses, price, start_date, end_date)
    returning * into rec;

    raise info 'Successfully added course package %', pid;
    return rec;
END
$$ language plpgsql;




/**
 * get_available_course_packages(): used to retrieve course packages that are available for sale
 */
CREATE OR REPLACE FUNCTION get_available_course_packages()
RETURNS TABLE (id int, name text, num_free_course_sessions int, end_date date, price float) AS $$
    select package_id, name, num_free_registrations, sale_end_date, price
    from course_packages
    where current_date between sale_start_date and sale_end_date
    order by sale_end_date asc;
$$ language sql;




/**
 * buy_course_package(): used when customer requests to purchase a course package
 */
CREATE OR REPLACE FUNCTION buy_course_package(cid int, pid int)
RETURNS buys AS $$
DECLARE
    rec buys;
    active_card Credit_cards;
    n_redemptions int;
BEGIN
    
    if (pid not in (select id from get_available_course_packages())) then
        raise exception 'Course package % is not available', pid
            using hint = 'Check for available courses using get_available_course_packages()';
            
        return NULL;
    end if;

    select * into active_card 
    from get_active_card(cid);
    
    select num_free_registrations into n_redemptions
    from Course_packages C
    where C.package_id = pid;

    --  at_most_one_package trigger on Buys ensures at most one (partially) active package
    set constraints at_most_one_package immediate;

    insert into Buys
    values (current_date, cid, active_card.card_number, pid, n_redemptions)
    returning * into rec;
    
    raise info 'Successfully bought course package % for customer %', pid, cid;

    return rec;
END
$$ language plpgsql;




/**
 * get_my_course_package(): 
 *  - used when a customer requests to view his/her active/partially active course package
 */
CREATE OR REPLACE FUNCTION get_my_course_package(cid int)
RETURNS json AS $$
DECLARE
    active_package record;
    redeemed_sessions json;
    out_json json;
BEGIN
    
    select * into active_package
    from Buys B
    where cust_id = cid and
        (num_remaining_redemptions > 0 or
            exists(select 1
                from Redeems R natural join Sessions
                where R.cust_id = cid and
                    R.buy_date = B.buy_date and
                    R.package_id = B.package_id and
                    current_date + 7 <= launch_date));

    if not found then 
        raise info 'No active/partially active course package for customer %', cid;
        return out_json;
    end if;

    select array_to_json(array_agg(t)) into redeemed_sessions
    from (
        select title as course_name, session_date, start_time as session_start_time
        from Redeems R natural join Sessions natural join Courses
        where active_package.cust_id = R.cust_id and
            active_package.buy_date = R.buy_date and
            active_package.package_id = R.package_id
        order by
            session_date asc,
            start_time asc
    ) t;


    select row_to_json(p) into out_json
    from (
        select C.name as package_name, 
            active_package.buy_date as purchase_date, 
            price, 
            num_free_registrations as num_free_sessions,
            active_package.num_remaining_redemptions as num_remaining_sessions,
            redeemed_sessions
        from Course_packages C
        where active_package.package_id = C.package_id
    ) p;
    
    return out_json;
END
$$ language plpgsql;




/**
 * TODO: get_my_course_package(): 
 *  - used when a customer requests to view his/her active/partially active course package
 */
