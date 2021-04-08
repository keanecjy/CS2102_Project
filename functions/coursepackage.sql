/*****************
 * User functions
 *****************/

/** 
 * add_course_pacakage(): used to add a new course package
 */ 
CREATE OR REPLACE PROCEDURE add_course_package(name text, num_sessions int, 
    start_date date, end_date date, price numeric)
AS $$
DECLARE
    pid int;
BEGIN
    -- generate id
    select coalesce(max(package_id), 0) + 1 into pid
    from course_packages;

    -- insert into course packages
    insert into course_packages 
    values (pid, name, num_sessions, price, start_date, end_date);
END
$$ language plpgsql;




/**
 * get_available_course_packages(): used to retrieve course packages that are available for sale
 */
CREATE OR REPLACE FUNCTION get_available_course_packages()
RETURNS TABLE (name text, num_free_course_sessions int, end_date date, price numeric) AS $$
    select name, num_free_registrations, sale_end_date, price
    from course_packages
    where current_date between sale_start_date and sale_end_date
    order by sale_end_date asc;
$$ language sql;




/**
 * buy_course_package(): used when customer requests to purchase a course package
 */
CREATE OR REPLACE PROCEDURE buy_course_package(cid int, pid int)
AS $$
DECLARE
    active_card Credit_cards;
    n_redemptions int;
BEGIN
    -- get required details
    select * into active_card from get_active_card(cid);
    
    select num_free_registrations into n_redemptions
    from Course_packages C
    where C.package_id = pid;

    if not found then
        raise exception 'Course package % does not exist', pid;
    end if;

    -- buying course package
    insert into Buys
    values (current_date, cid, active_card.card_number, pid, n_redemptions);
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
                from Redeems R natural join Sessions S
                where R.cust_id = cid and
                    R.buy_date = B.buy_date and
                    R.package_id = B.package_id and
                    current_date + 7 <= S.session_date));

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
 * top_packages(): 
 *  - used to find the top N course packages for this year.
 */
CREATE OR REPLACE FUNCTION top_packages(N int)
RETURNS TABLE (
    package_id int,
    num_free_sessions int,
    price numeric,
    start_date date,
    end_date date,
    number_sold bigint
) AS $$
DECLARE
    curs refcursor;
    r record;
    prev_sold int;

    current_year double precision;
BEGIN

    if (N < 0) then
        raise exception 'The given input N cannot be negative: %', N;
    end if;

    -- get current year
    select date_part into current_year
    from date_part('year', current_date);

    create temporary table if not exists temp_table on commit drop as
        select P.*, coalesce(count(buy_date), 0) as number_sold
        from Course_packages P natural left join Buys B
        where date_part('year', sale_start_date) = current_year
        group by P.package_id;

    open curs for (
        select * from temp_table
        order by number_sold desc, price desc
    );

    while n >= 0 loop
        fetch curs into r;
        exit when not found;

        exit when n = 0 and r.number_sold <> prev_sold;

        package_id := r.package_id;
        num_free_sessions := r.num_free_registrations;
        price := r.price;
        start_date := r.sale_start_date;
        end_date := r.sale_end_date;
        number_sold := r.number_sold;

        prev_sold := number_sold;
        if (n > 0) then
            n := n - 1;
        end if;
        return next;
    end loop;
END
$$ language plpgsql;
