DROP TABLE IF EXISTS
Employees, Part_time_emp, Full_time_emp, Instructors, Part_time_instructors,
Full_time_instructors, Administrators, Managers, Pay_slips,
Rooms, Course_areas, Specializes, Courses, Offerings, Sessions,
Customers, Credit_cards, Course_packages, Buys, Redeems, Registers, Cancels
CASCADE;



/*************************************************
 * Personnels & Organisation-related Information
 ************************************************/

-- TODO: Covering constraint: eid must be in Part time or Full time but not both
CREATE TABLE Employees
(
    eid 		int primary key,
    name 		text not null,
    phone 		int not null,
    email 		text not null,
    address 	text not null,
    join_date 	date not null,
    depart_date date,

    CONSTRAINT correct_dates check (join_date <= depart_date)
);

-- TODO: Covering constraint: all part time employee must be part time instructors
CREATE TABLE Part_time_emp
(
    eid 		int primary key references Employees on delete cascade,
    hourly_rate float not null check (hourly_rate >= 0)
);

-- TODO: Covering constraint: all full time employee must be either Full_time instructors or administrators or managers
CREATE TABLE Full_time_emp
(
    eid 			int primary key references Employees on delete cascade,
    monthly_salary  float not null check (monthly_salary >= 0)
);

-- TODO: Covering constraint: all instructors must be either part-time or full-time instructors
CREATE TABLE Instructors
(
    eid int primary key references Employees on delete cascade
);

CREATE TABLE Part_time_instructors
(
    eid int primary key references Instructors
    references Part_time_emp on delete cascade
);

CREATE TABLE Full_time_instructors
(
    eid int primary key references Instructors
    references Full_time_emp on delete cascade
);

CREATE TABLE Administrators
(
    eid int primary key references Full_time_emp on delete cascade
);

CREATE TABLE Managers
(
    eid int primary key references Full_time_emp on delete cascade
);

CREATE TABLE Pay_slips
(
    eid 			int references Employees on delete cascade,
    payment_date 	date,
    amount 			float not null check (amount >= 0),
    num_work_days 	int check (num_work_days >= 0),
    num_work_hours  int check (num_work_hours >= 0),

    primary key (eid, payment_date)
);



/******************************************
 * Courses & Sessions-related Information
 *****************************************/

CREATE TABLE Rooms
(
    rid 			    int primary key,
    location 		    text not null,
    seating_capacity    int not null check (seating_capacity >= 0)
);

CREATE TABLE Course_areas
(
    area_name   text primary key,
    eid         int not null references Managers
);

-- TODO: Trigger - to enforce total participation, every Instructors has >= 1 specialisation
CREATE TABLE Specializes
(
    eid 		int references Instructors,
    area_name   text references Course_areas,

    primary key (eid, area_name)
);

CREATE TABLE Courses
(
    course_id 	int primary key,
    title 		text unique not null,
    description text not null,
    area_name 	text not null references Course_areas,
    duration 	int not null check (duration >= 0)
);

CREATE TABLE Offerings
(
    launch_date 				date not null,
    course_id 					int references Courses on delete cascade,

    registration_deadline       date not null,
    start_date 					date,
    end_date 					date,

    eid 						int not null references Administrators,

    target_number_registrations int not null check (target_number_registrations >= 0),
    seating_capacity 			int default 0,
    fees 						float not null check (fees >= 0),

    primary key (launch_date, course_id),
    CONSTRAINT correct_dates check (
        start_date <= end_date and
        start_date >= registration_deadline + interval '10 days' and 
        launch_date <= registration_deadline
    )
);

-- TODO: Trigger - to enforce total participation, every Offerings has >= 1 Sessions
-- TODO: Trigger - start date and end date of Offerings is updated to the earliest and latest session_date
-- TODO: Trigger - each instructor at most one course session at any hour
-- TODO: Trigger - each instructor must not teach 2 consecutive sessions (1 hr break)
-- TODO: Trigger - each part-time instructor total hours per month <= 30
-- TODO: Trigger - the assigned instructor must specialise in that course_area
-- TODO: Trigger - update seating_capacity in Offerings to sum of seating capacities of sessions
-- TODO: Trigger - Each room can be used to conduct at most one course session at any time
-- TODO: Trigger - This constraint have to be in trigger as subquery not allowed in check 
--  CONSTRAINT is_week_day check (select extract(dow from session_date) in (1,2,3,4,5))
CREATE TABLE Sessions
(
    sid 			int,
    launch_date 	date,
    course_id 		int,

    session_date    date not null,
    start_time 		time not null,
    end_time 		time not null,

    rid 			int references Rooms not null,
    eid 			int references Instructors not null,

    primary key (sid, launch_date, course_id),
    foreign key (launch_date, course_id) references Offerings on delete cascade,

    CONSTRAINT valid_hours check (start_time <= end_time),
    CONSTRAINT within_working_hours check (TIME '09:00' <= start_time and end_time <= TIME '18:00'),
    CONSTRAINT not_within_lunch_hours check (NOT (start_time, end_time) OVERLAPS (TIME '12:00', TIME '14:00'))
);



/*************************
 * Customers Information
 ************************/

CREATE TABLE Customers
(
    cust_id int primary key,
    name 	text not null,
    address text not null,
    phone 	int not null,
    email 	text not null,

    unique(name, address, phone, email)
);

-- TODO: Trigger - to enforce total participation, every customer have at least one card (on delete or update)
CREATE TABLE Credit_cards
(
    -- card_number can begin with 0
    card_number text primary key,
    CVV 		int not null,
    expiry_date date not null,

    cust_id 	int not null references Customers,
    from_date 	date not null,

    unique(cust_id, card_number),
    CONSTRAINT valid_card_number check (
        (card_number ~ '^\d*$') and (length(card_number) between 8 and 19)
    ),
    CONSTRAINT vaild_cvv check (length(CVV::text) in (3, 4))
);



/*******************************
 * Purchase-related Information
 *******************************/

CREATE TABLE Course_packages
(
    package_id 				int primary key,
    name 					text not null,
    num_free_registrations 	int not null check (num_free_registrations >= 0),
    price 					float not null check (price >= 0),
    sale_start_date 		date not null,
    sale_end_date 			date not null,

    CONSTRAINT correct_dates check (sale_start_date <= sale_end_date)
);

-- TODO: TRIGGER - each customer can have at most one active or partially active package (trigger on add)
-- NOTE: card_number not part of pri key
CREATE TABLE Buys
(
    buy_date 					date not null,
    cust_id 					int,
    card_number 				text,
    package_id 					int references Course_packages,
    num_remaining_redemptions   int not null check (num_remaining_redemptions >= 0),

    primary key (buy_date, cust_id, package_id),
    foreign key (cust_id, card_number) references Credit_cards (cust_id, card_number)
);

-- NOTE: card_number not included as an attribute
CREATE TABLE Redeems
(
    redeem_date date not null,

    buy_date    date,
    cust_id     int,
    package_id  int,

    sid         int,
    launch_date date,
    course_id   int,

    primary key (redeem_date, buy_date, cust_id, package_id, sid, launch_date, course_id),
    foreign key (buy_date, cust_id, package_id) references Buys,
    foreign key (sid, launch_date, course_id) references Sessions
);

-- TODO: TRIGGER - For each course offered by the company, a customer can register for at most one of its sessions before its registration deadline.
-- TODO: TRIGGER - course offering is said to be available if the number of registrations received is no more than its seating capacity; otherwise, we say that a course offering is fully booked
-- NOTE: card_number not part of pri key
CREATE TABLE Registers
(
    register_date   date not null,

    cust_id 		int,
    card_number 	text,

    sid 			int,
    launch_date 	date,
    course_id 		int,

    primary key (register_date, cust_id, sid, launch_date, course_id),
    foreign key (cust_id, card_number) references Credit_cards(cust_id, card_number),
    foreign key (sid, launch_date, course_id) references Sessions
);

CREATE TABLE Cancels
(
    cancel_date 	date not null,
    refund_amt      float,
    package_credit  int,

    cust_id 		int references Customers,

    sid 			int,
    launch_date 	date,
    course_id 		int,

    primary key (cancel_date, cust_id, sid, launch_date, course_id),
    foreign key (sid, launch_date, course_id) references Sessions,
    CONSTRAINT refund_value check (
        (refund_amt is not null and package_credit is null) or
        (refund_amt is null and package_credit is not null)
    )
);
