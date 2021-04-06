CREATE OR REPLACE PROCEDURE register_session(cus_id INT, in_cid INT, date_of_launch DATE, session_number INT, pay_method TEXT)
AS $$
DECLARE
    pid int;
    num_card TEXT;
    date_of_buy DATE;
BEGIN
    /*
     * 1) Check if current_date have already past the session_date itself
     * 2) Check if current_date have already past the registration_deadline
     * 3) Check if number of registration + redeems <= seating_capacity
     * 4) If redeems, check if the number of redeems of that package_id < num_free_registrations. Means check if package is active?
     * 5) Check if there is any session of this course that exist before (In unique_session_per_course_redeem_checks AND unique_session_per_course_register_checks)
     */
    /*
     * Dont need to check validity of buy_date, pid, card_number, session_number, cid, date_of_launch etc as it should be check via the foreign key?
     */

    IF (pay_method = 'redeem') THEN

        SELECT buy_date, package_id INTO date_of_buy, pid
        FROM Buys B
        WHERE B.cust_id = cus_id AND B.num_remaining_redemptions > 0;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer % does not have an active course package that is available for free redemptions', cus_id;
        END IF;

        INSERT INTO Redeems VALUES (current_date, date_of_buy, cus_id, pid, session_number, date_of_launch, in_cid);

    ELSIF (pay_method = 'card') THEN
        SELECT card_number INTO num_card FROM get_active_card(cus_id);
        
        INSERT INTO Registers VALUES (current_date, cus_id, num_card, session_number, date_of_launch, in_cid);
    ELSE
        RAISE EXCEPTION 'INVALID PAYMENT METHOD';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE cancel_registration(cus_id INT, in_cid INT, date_of_launch DATE)
AS $$
DECLARE
    sid_register INT;
    sid_redeem INT;
BEGIN
    -- we know that for a course, that customer only have 1 session
    -- if cancelled at least 7 days before the day of registered sessions, will have to credit an extra course session to customer 
    SELECT R.sid INTO sid_redeem
    FROM Redeems R
    WHERE R.cust_id = cus_id
      AND R.course_id = in_cid
      AND R.launch_date = date_of_launch;

    SELECT R.sid INTO sid_register
    FROM Registers R
    WHERE R.cust_id = cus_id
      AND R.course_id = in_cid
      AND R.launch_date = date_of_launch;

    IF (sid_redeem IS NULL AND sid_register IS NULL) THEN
        RAISE EXCEPTION 'This customer does not have any session for this course';
    END IF;

    IF (sid_redeem IS NOT NULL) THEN
        -- DELETE FROM redeems
        DELETE FROM Redeems R
        WHERE R.cust_id = cus_id
          AND R.course_id = in_cid
          AND R.launch_date = date_of_launch;
    ELSE
        -- DELETE FROM registers
        DELETE FROM Registers R
        WHERE R.cust_id = cus_id
          AND R.course_id = in_cid
          AND R.launch_date = date_of_launch;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- course_name = title
-- sorted by session_date, start_hour
-- course_name, duration (Courses)
-- course_fee (Offerings)
-- session_date, start_hour (Sessions)
-- Instructor_name (Specializes)
CREATE OR REPLACE FUNCTION get_my_registrations(IN cus_id INT)
    RETURNS TABLE (course_name TEXT, course_fee FLOAT, session_date DATE, start_hour TIME, duration INT, instructor_name TEXT) AS $$
DECLARE
BEGIN
    return query
    with
        Q0 AS (SELECT launch_date, course_id, fees FROM Offerings),
        Q1 AS (SELECT * FROM (Employees NATURAL JOIN Specializes NATURAL JOIN Courses NATURAL JOIN Q0 NATURAL JOIN Sessions)),
        Q2 AS (SELECT * FROM (Q1 NATURAL JOIN Redeems) A WHERE cust_id = cus_id AND A.session_date > current_date),
        Q3 AS (SELECT * FROM (Q1 NATURAL JOIN Registers) B WHERE cust_id = cus_id AND B.session_date > current_date)
    SELECT *
    FROM (SELECT Q2.title, Q2.fees, Q2.session_date, Q2.start_time, Q2.duration, Q2.name FROM Q2
          UNION
          SELECT Q3.title, Q3.fees, Q3.session_date, Q3.start_time, Q3.duration, Q3.name FROM Q3) AS ANS
    ORDER BY (ANS.session_date, ANS.start_time);
END;
$$ LANGUAGE plpgsql;




