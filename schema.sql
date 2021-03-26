DROP TABLE IF EXISTS Customers, Credit_cards, Course_packages, Buys, Employees, Part_time_emp, Full_time_emp, Instructors, Part_time_instructors, Full_time_instructors, Administrators, Managers, Pay_slips, Rooms, Course_areas, Specializes, Courses, Offerings, Sessions, Cancels, Registers, Redeems CASCADE;

CREATE TABLE Customers
(
    cust_id int primary key,
    address text,
    phone   int,
    email   text
);

CREATE TABLE Credit_cards
(
    card_number int primary key,
    CVV         int,
    expiry_date date,
    from_date   date,
    cust_id     int not null references Customers
);
-- if delete or update to change cust_id, ensure that OLD.cust_id have another credit card.
-- need trigger to ensure that every customer have at least one credit card

CREATE TABLE Course_packages
(
    package_id             int primary key,
    name                   text,
    price                  float,
    sale_start_date        date,
    sale_end_date          date,
    num_free_registrations int
);

CREATE TABLE Buys
(
    num_remaining_redemptions int not null,
    buy_date                  date,
    card_number               int references Credit_cards,
    package_id                int references Course_packages,
    primary key (buy_date, card_number, package_id)
);

-- Covering constraint on Employees: eid must be in Part time or Full time but not both
create table Employees
(
    join_date   date,
    depart_date date,
    address     text,
    email       text,
    phone       integer,
    name        text,
    eid         integer primary key
);

-- Covering constraint on Part_time_emp: all part time employee must be part time instructors
create table Part_time_emp
(
    hourly_rate float,
    eid         integer primary key references Employees on delete cascade
);

-- Covering constraint on Full_time_emp: all full time employee must be either Full_time instructors or administrators or managers
create table Full_time_emp
(
    monthly_salary float,
    eid            integer primary key references Employees on delete cascade
);

-- Covering constraint on Instructors: all instructors must be either part-time or full-time instructors
CREATE TABLE Instructors
(
    eid int primary key references Employees on delete cascade
);

CREATE TABLE Part_time_instructors
(
    eid int primary key references Instructors
        references Part_time_Emp on delete cascade
);

CREATE TABLE Full_time_instructors
(
    eid int primary key references Instructors
        references Full_time_Emp on delete cascade
);

create table Administrators
(
    eid integer primary key references Full_time_Emp on delete cascade
);

create table Managers
(
    eid integer primary key references Full_time_Emp on delete cascade
);

CREATE TABLE Pay_slips
(
    amount         float,
    payment_date   date,
    num_work_hours int,
    num_work_days  int,
    eid            integer references Employees on delete cascade,
    primary key (eid, payment_date)
);

CREATE TABLE Rooms
(
    rid              integer primary key,
    location         text,
    seating_capacity int
);

CREATE TABLE Course_areas
(
    area_name text primary key,
    eid       int not null references Managers
);

-- need trigger to enforce total participation of Specializes on Instructors
CREATE TABLE Specializes
(
    eid       integer references Instructors,
    area_name text references Course_areas,
    primary key (area_name, eid)
);

CREATE TABLE Courses
(
    course_id   int primary key,
    duration    int,
    description text,
    title       text,
    area_name   text not null references Course_areas
);

-- if delete or update to change sid, ensure that the OLD offerings have at least one sid.
-- need trigger to ensure that every offerings have at least one sessions
-- Trigger on sessions?
CREATE TABLE Offerings
(
    launch_date                 date,
    course_id                   int references Courses on delete cascade,
    start_date                  date,
    end_date                    date,
    registration_deadline       date,
    target_number_registrations int,
    seating_capacity            int,
    fees                        float,
    eid                         int not null references Administrators,
    primary key (launch_date, course_id)
);

CREATE TABLE Sessions
(
    sid          int,
    launch_date  date,
    course_id    int,
    session_date date,
    start_time   time,
    end_time     time,
    rid          int references Rooms       not null,
    eid          int references Instructors not null,
    primary key (sid, launch_date, course_id),
    foreign key (launch_date, course_id) references Offerings on delete cascade
);

CREATE TABLE Cancels
(
    cancellation_date date,
    refund_amt        float,
    package_credit    float,
    sid               int,
    launch_date       date,
    course_id         int,
    cust_id           integer references Customers,
    foreign key (sid, launch_date, course_id) references Sessions,
    primary key (cancellation_date, cust_id, sid, launch_date, course_id)
);

CREATE TABLE Registers
(
    register_date date,
    card_number   int references Credit_cards,
    sid           int,
    launch_date   date,
    course_id     int,
    foreign key (sid, launch_date, course_id) references Sessions,
    primary key (register_date, card_number, sid, launch_date, course_id)
);

CREATE TABLE Redeems
(
    buy_date    date,
    redeem_date date,
    package_id  int,
    card_number int,
    sid         int,
    launch_date date,
    course_id   int,
    foreign key (sid, launch_date, course_id) references Sessions,
    foreign key (buy_date, card_number, package_id) references Buys,
    primary key (buy_date, card_number, package_id, redeem_date, sid, launch_date, course_id)
);


