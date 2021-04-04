BEGIN;

SET CONSTRAINTS ALL DEFERRED;

/**********************************************
 * Personnels & Organisation-related
 *********************************************/

INSERT INTO Employees (eid, name, phone, email, address, join_date) VALUES 
(1, 'Nye Vidgen', '83011564', 'nvidgen0@fastcompany.com', '1 Transport Way', '10/25/2020'),
(2, 'Kacy Faltskog', '89716842', 'kfaltskog1@jiathis.com', '5 Kennedy Hill', '10/25/2020'),
(3, 'Moira Dawbery', '94248921', 'mdawbery2@usda.gov', '136 Artisan Court', '5/8/2020'),
(4, 'Sharl Kinghorn', '99037408', 'skinghorn3@wisc.edu', '5 Surrey Lane', '5/23/2020'),
(5, 'Kalle Kusick', '64118900', 'kkusick4@phoca.cz', '2334 Veith Center', '12/27/2020'),
(6, 'Dasya Dunton', '95548942', 'ddunton5@engadget.com', '768 Quincy Avenue', '7/13/2020'),
(7, 'Ranique Luetkemeyers', '87298275', 'rluetkemeyers6@mapy.cz', '5 Pawling Crossing', '10/27/2020'),
(8, 'Leonhard Groundwater', '99051668', 'lgroundwater7@theguardian.com', '5863 Schiller Street', '9/2/2020'),
(9, 'Brandie Ziemens', '91643842', 'bziemens8@merriam-webster.com', '03 Kennedy Trail', '9/26/2020'),
(10, 'Andre Inchcomb', '95993026', 'ainchcomb9@webnode.com', '2 Lakewood Road', '12/8/2020'),
(11, 'Gipsy Chivrall', '98816199', 'gchivralla@icq.com', '63121 Fulton Alley', '3/22/2021'),
(12, 'Archie Brunskill', '89790645', 'abrunskillb@elegantthemes.com', '9163 Maryland Street', '9/22/2020'),
(13, 'Justino Teliga', '63433137', 'jteligac@oaic.gov.au', '4 Boyd Trail', '7/9/2020'),
(14, 'Caralie Ewbanks', '92983007', 'cewbanksd@over-blog.com', '98111 Morrow Point', '1/21/2021'),
(15, 'Brose Scollard', '82476370', 'bscollarde@archive.org', '29008 Dwight Court', '9/13/2020'),
(16, 'Faunie Goacher', '93562662', 'fgoacherf@mozilla.com', '42 Nobel Court', '12/9/2020'),
(17, 'Pamella MacAskie', '86706014', 'pmacaskieg@tripod.com', '6 Merrick Road', '6/17/2020'),
(18, 'Caspar Singyard', '93343021', 'csingyardh@kickstarter.com', '4936 Judy Street', '7/15/2020'),
(19, 'Zelig Scorer', '99231978', 'zscoreri@cmu.edu', '8656 Stone Corner Trail', '1/1/2021'),
(20, 'Lotta Terne', '99553768', 'lternej@columbia.edu', '00 Shasta Trail', '1/1/2021'),
(21, 'Kelbee Ludwell', '65008733', 'kludwellk@macromedia.com', '90 Graedel Lane', '1/27/2021'),
(22, 'Tripp Eskriet', '88445592', 'teskrietl@narod.ru', '93 Packers Plaza', '11/19/2020'),
(23, 'Shea Kob', '94325785', 'skobm@domainmarket.com', '4115 Esch Crossing', '10/7/2020'),
(24, 'Ann Dodswell', '90191129', 'adodswelln@t-online.de', '82061 Miller Point', '8/9/2020'),
(25, 'Raymond Lepope', '60144261', 'rlepopeo@ucla.edu', '2 Main Plaza', '9/4/2020'),
(26, 'Hertha Lobley', '60795459', 'hlobleyp@bloglines.com', '6997 Ridgeway Court', '2/27/2021'),
(27, 'Johnna Wyss', '82608424', 'jwyssq@altervista.org', '8889 Surrey Pass', '8/25/2020'),
(28, 'Dane Weber', '65967734', 'dweberr@moonfruit.com', '1 Holmberg Crossing', '2/24/2021'),
(29, 'Debi D''Ambrosio', '95556948', 'ddambrosios@woothemes.com', '65773 Stephen Place', '12/20/2020'),
(30, 'Carmelia Dregan', '94333915', 'cdregant@cnet.com', '7021 Arrowood Hill', '10/17/2020'),
(31, 'Lev Giannazzo', '97588714', 'lgiannazzou@slideshare.net', '66 Bashford Road', '5/13/2020'),
(32, 'Russ Tummons', '90527781', 'rtummonsv@usatoday.com', '956 American Ash Alley', '1/31/2021'),
(33, 'Rosemary Blagden', '98353734', 'rblagdenw@t.co', '531 Westport Avenue', '11/19/2020'),
(34, 'Eve Swansbury', '96703118', 'eswansburyx@bbc.co.uk', '40 Armistice Plaza', '3/4/2021'),
(35, 'Jerald Logan', '66658405', 'jlogany@google.it', '2 Everett Lane', '6/8/2020'),
(36, 'Frederick Lewty', '66955229', 'flewtyz@163.com', '983 Upham Street', '7/12/2020'),
(37, 'Jae Gippes', '94666112', 'jgippes10@skyrock.com', '760 Northport Alley', '9/27/2020'),
(38, 'Darwin Pillifant', '86795443', 'dpillifant11@issuu.com', '57 Anderson Hill', '6/10/2020'),
(39, 'Hi Christensen', '98789416', 'hchristensen12@rakuten.co.jp', '24474 Dapin Court', '9/30/2020'),
(40, 'Cordelie Laugheran', '90505833', 'claugheran13@dedecms.com', '473 Carey Alley', '9/20/2020'),
(41, 'mr part-time', '99991111', 'pt@nus.edu.sg', 'sad tree', '9/20/2020'),
(42, 'manager4pt', '12312312', 'man@nus.edu.sg', 'sad tree2', '8/20/2020'),
(43, 'admin4pt', '12341234', 'adminpt@nus.edu.sg', 'sad tree3', '7/20/2020'),
(44, 'mr part-time free', '44443333', '44443333@nus.edu.sg', 'sad tree4', '10/20/2020'),
(45, 'mr full-time free', '54443333', '54443333@nus.edu.sg', 'sad tree5', '10/20/2020');

INSERT INTO Part_time_emp (eid, hourly_rate) VALUES
(4, 14.50), (7, 8.00), (9, 10.80), (10, 16.00), (12, 12.00),
(21, 12.50), (23, 13.00), (24, 9.60), (29, 13.50), (37, 10.00), (41, 9.95), (44, 12.20);


INSERT INTO Full_time_emp (eid, monthly_salary) VALUES
-- Full-time instructors
(2, 5450), (14, 6010), (20, 3800), (25, 2450), (31, 8120),
(35, 3450), (36, 3650), (38, 4100), (39, 4210), (40, 7754), (45, 9999),
-- Administrators
(1, 5400), (3, 5830), (5, 4590), (6, 3390), (15, 5480),
(17, 5000), (26, 4100), (28, 4000), (32, 3800), (33, 6100), (43, 1000),
-- Managers
(8, 4800), (11, 6200), (13, 5490), (16, 5210), (18, 4490),
(19, 4500), (22, 7700), (27, 5500), (30, 4320), (34, 3910), (42, 4000);


INSERT INTO Instructors (eid) VALUES
(2), (4), (7), (9), (10), (12), (14), (20), (21), (23), 
(24), (25), (29), (31), (35), (36), (37), (38), (39), (40), (41), (44), (45);


INSERT INTO Part_time_instructors (eid) VALUES
(4), (7), (9), (10), (12), (21), (23), (24), (29), (37), (41), (44);


INSERT INTO Full_time_instructors (eid) VALUES
(2), (14), (20), (25), (31), (35), (36), (38), (39), (40), (45);


INSERT INTO Administrators (eid) VALUES
(1), (3), (5), (6), (15), (17), (26), (28), (32), (33), (43);


INSERT INTO Managers (eid) VALUES
(8), (11), (13), (16), (18), (19), (22), (27), (30), (34), (42);


/**
 * TODO: Pay_slips table to be populated by function calls
 */



/**********************************************
 * Courses & Sessions-related Information
 *********************************************/

INSERT INTO Rooms (rid, location, seating_capacity) VALUES
(1, 'Level 2, Seminar Room 1', 250), 
(2, 'Level 2, Lecture Hall 1', 500), 
(3, 'Level 4, Lecture Hall 2', 400), 
(4, 'Level 3, Seminar Room 2', 200), 
(5, 'Level 4, Seminar Room 3', 250), 
(6, 'Level 5, Lecture Hall 3', 300), 
(7, 'Level 5, Lecture Hall 4', 450), 
(8, 'Level B1, Lecture Hall 8', 400), 
(9, 'Level 6, Seminar Room 3', 250), 
(10, 'Level 6, Conference Room 6', 100);


INSERT INTO Course_areas (area_name, eid) VALUES
('Algorithms & Theory', 11),
('Artificial Intelligence', 11),
('Computer Graphics & Games', 8),
('Computer Security', 13),
('Database Systems', 22),
('Multimedia', 19),
('Computer Networks', 16), 
('Parallel Computing', 19), 
('Programming Languages', 27),
('Software Engineering', 30),
('course1', 42),
('course2', 42),
('course3', 42),
('course4', 42),
('course5', 42),
('course6', 42);
                                                 

INSERT INTO Specializes (eid, area_name) VALUES
(2, 'Algorithms & Theory'), (4, 'Software Engineering'),
(7, 'Artificial Intelligence'), (9, 'Database Systems'),
(10, 'Computer Networks'), (12, 'Programming Languages'),
(14, 'Computer Security'), (20, 'Software Engineering'),
(21, 'Computer Graphics & Games'), (23, 'Artificial Intelligence'),
(24, 'Parallel Computing'), (25, 'Computer Graphics & Games'),
(29, 'Artificial Intelligence'), (31, 'Algorithms & Theory'),
(35, 'Computer Networks'), (36, 'Database Systems'),
(37, 'Software Engineering'), (38, 'Database Systems'),
(39, 'Artificial Intelligence'), (40, 'Database Systems'),
(41, 'course1'), (41, 'course2'), (41, 'course3'), (41, 'course4'),(41, 'course5'), (41, 'course6'),
(44, 'course1'), (44, 'course2'), (44, 'course3'), (44, 'course4'),(44, 'course5'), (44, 'course6'),
(45, 'course1'), (45, 'course2'), (45, 'course3'), (45, 'course4'),(45, 'course5'), (45, 'course6');


INSERT INTO Courses (course_id, title, description, area_name, duration) VALUES
(2102, 'Database Systems', 'Learn about PSQL, Schemas and Relatiional Algebra!', 'Database Systems', 1),
(3230, 'Design and Analysis of Algorithms', 'Crash course to master Leetcode challenges', 'Algorithms & Theory', 3),
(3223, 'Database Systems Implementation', 'Learn how to implement a DBMS', 'Database Systems', 2),
(3243, 'Intro to AI', 'Pick up the basics of AI and automate your lifestyle', 'Artificial Intelligence', 2),
(3247, 'Game Development', 'Learn to create your own game in this 2 hour course', 'Computer Graphics & Games', 2),
(2107, 'Intro to Information Security', 'Learn about the basics of ethical hacking', 'Computer Security', 1),
(2105, 'Intro to Computer Networks', 'Are you sure you know how the internet works?', 'Computer Networks', 1),
(5224, 'Cloud Computing', 'Jump onto the hype and learn more about Cloud Technology', 'Parallel Computing', 3),
(2104, 'Programming Language Concepts', 'Learn up to 8 different programming languages in an hour', 'Programming Languages', 1),
(2103, 'Software Engineering', 'Hello, I am Duke, lets learn to build an address book!', 'Software Engineering', 1),
(1, 'course1', 'c1', 'course1', 3),
(2, 'course2', 'c2', 'course2', 3),
(3, 'course3', 'c3', 'course3', 3),
(4, 'course4', 'c4', 'course4', 3),
(5, 'course5', 'c5', 'course5', 3),
(6, 'course6', 'c6', 'course6', 3);

INSERT INTO Offerings (launch_date, course_id, registration_deadline, start_date, end_date, eid, target_number_registrations, seating_capacity, fees) VALUES
('12/24/2020', 2102, '1/28/2021', '2/11/2021', '2/12/2021', 32, 85, 1000, 181.40),
('2/7/2021', 2103, '3/27/2021', '4/8/2021', '4/8/2021', 15, 70, 250, 55.65),
('1/8/2021', 3223, '2/7/2021', '2/17/2021', '2/17/2021', 1, 58, 200, 136.50),
('11/16/2020', 5224, '12/12/2020', '12/30/2020', '4/20/2021', 3, 75, 500, 68.50),
('3/16/2021', 5224, '5/2/2021', '5/28/2021', '5/28/2021', 3, 75, 250, 69.50),
('3/4/2021', 3243, '5/8/2021', '5/18/2021', '5/18/2021', 28, 80, 100, 186.00),
('3/11/2021', 2105, '4/26/2021', '5/14/2021', '5/14/2021', 28, 50, 400, 91.00),
('12/13/2020', 2104, '1/30/2021', '2/12/2021', '2/12/2021', 6, 50, 250, 187.30),
('2/13/2021', 2102, '4/7/2021', '4/19/2021', '4/19/2021', 33, 55, 200, 75.50),
('3/7/2020', 3247, '4/28/2021', '5/10/2021', '5/10/2021', 33, 68, 100, 155.50),
('4/18/2021', 3230, '5/10/2021', '5/20/2021', '5/20/2021', 17, 100, 500, 137.77),
('4/1/2021', 1, '4/10/2021', '4/20/2021', '4/30/2021', 43, 100, 250, 250),
('4/2/2021', 2, '4/11/2021', '4/21/2021', '4/30/2021', 43, 100, 250, 250),
('4/1/2021', 3, '4/10/2021', '4/20/2021', '4/30/2021', 43, 100, 250, 250),
('4/2/2021', 4, '4/11/2021', '4/21/2021', '4/30/2021', 43, 100, 250, 250),
('4/1/2021', 5, '4/10/2021', '4/20/2021', '4/30/2021', 43, 100, 250, 250),
('4/2/2021', 6, '4/11/2021', '4/21/2021', '4/30/2021', 43, 100, 250, 250);

INSERT INTO Sessions (sid, launch_date, course_id, session_date, start_time, end_time, rid, eid)
VALUES
(1, '12/24/2020', 2102, '2/11/2021', '10:00', '11:00', 1, 36),
(2, '12/24/2020', 2102, '2/11/2021', '14:00', '15:00', 1, 9),
(3, '12/24/2020', 2102, '2/12/2021', '15:00', '16:00', 2, 38),
(1, '2/7/2021', 2103, '4/8/2021', '17:00', '18:00', 5, 20),
(1, '1/8/2021', 3223, '2/17/2021', '15:00', '17:00', 4, 38),
(1, '11/16/2020', 5224, '12/30/2020', '14:00', '17:00', 1, 24),
(1, '3/16/2021', 5224, '5/18/2021', '14:00', '17:00', 1, 24),
(1, '3/4/2021', 3243, '5/18/2021', '15:00', '17:00', 8, 7),
(1, '3/11/2021', 2105, '5/4/2021', '10:00', '11:00', 8, 10),
(1, '12/13/2020', 2104, '2/12/2021', '14:00', '15:00', 1 ,12),
(1, '2/13/2021', 2102, '4/19/2021', '11:00', '12:00', 4, 9),
(1, '3/7/2020', 3247, '5/10/2021', '16:00', '18:00', 10, 21),
(1, '4/18/2021', 3230, '5/20/2021', '15:00', '18:00', 2, 2),
-- this makes eid = 41 part time teach = 30 hours
(1, '4/1/2021', 1, '4/26/2021', '09:00', '12:00', 1, 41),
(2, '4/1/2021', 1, '4/26/2021', '14:00', '17:00', 1, 41),
(3, '4/1/2021', 1, '4/27/2021', '09:00', '12:00', 1, 41),
(4, '4/1/2021', 1, '4/27/2021', '14:00', '17:00', 1, 41),
(5, '4/1/2021', 1, '4/28/2021', '09:00', '12:00', 1, 41),
(6, '4/1/2021', 1, '4/28/2021', '15:00', '18:00', 1, 41),
(7, '4/1/2021', 1, '4/29/2021', '09:00', '12:00', 1, 41),
(1, '4/2/2021', 2, '4/29/2021', '15:00', '18:00', 1, 41),
(2, '4/2/2021', 2, '4/30/2021', '09:00', '12:00', 1, 41),
(3, '4/2/2021', 2, '4/30/2021', '14:00', '17:00', 1, 41),
-- this make eid = 44 part time teach < 30 hours
(8, '4/1/2021', 3, '4/26/2021', '09:00', '12:00', 2, 44),
(9, '4/1/2021', 3, '4/26/2021', '14:00', '17:00', 2, 44),
(4, '4/2/2021', 4, '4/28/2021', '09:00', '12:00', 2, 44),
(5, '4/2/2021', 4, '4/28/2021', '15:00', '18:00', 2, 44),
-- this makes eid = 45 teach = 30 hours
(10, '4/1/2021', 5, '4/26/2021', '09:00', '12:00', 3, 45),
(11, '4/1/2021', 5, '4/26/2021', '14:00', '17:00', 3, 45),
(12, '4/1/2021', 5, '4/27/2021', '09:00', '12:00', 3, 45),
(13, '4/1/2021', 5, '4/27/2021', '15:00', '18:00', 3, 45),
(14, '4/1/2021', 5, '4/28/2021', '09:00', '12:00', 3, 45),
(15, '4/1/2021', 5, '4/28/2021', '14:00', '17:00', 3, 45),
(16, '4/1/2021', 5, '4/29/2021', '09:00', '12:00', 3, 45),
(6, '4/2/2021', 6, '4/29/2021', '15:00', '18:00', 3, 45),
(7, '4/2/2021', 6, '4/30/2021', '09:00', '12:00', 3, 45),
(8, '4/2/2021', 6, '4/30/2021', '14:00', '17:00', 3, 45);


/************************
 * Customers Information
 ***********************/

INSERT INTO Customers (cust_id, name, address, phone, email)
VALUES
(1, 'Denni Goacher', '7706 Waubesa Avenue', '62015347', 'dgoacher0@noaa.gov'),
(2, 'Bernadina Cadwaladr', '44 Maryland Lane', '90269894', 'bcadwaladr1@time.com'),
(3, 'Cirillo Winwright', '544 Manitowish Hill', '94617090', 'cwinwright2@skype.com'),
(4, 'Luci Castelli', '389 Cascade Crossing', '90908386', 'lcastelli3@wunderground.com'),
(5, 'Jelene Eskrick', '2 Bartillon Plaza', '60570869', 'jeskrick4@ted.com'),
(6, 'Murielle Alldridge', '02 Shasta Road', '69972108', 'malldridge5@comcast.net'),
(7, 'Abagael Slator', '5 Helena Park', '96625468', 'aslator6@sun.com'),
(8, 'Sammy Kasper', '7553 Blaine Crossing', '62759930', 'skasper7@geocities.jp'),
(9, 'Debee Rawle', '42 Garrison Hill', '91718810', 'drawle8@domainmarket.com'),
(10, 'Celinda Suter', '75560 Di Loreto Hill', '94576929', 'csuter9@toplist.cz'),
(11, 'Arnaldo Twoohy', '2 Truax Trail', '99792673', 'atwoohya@github.io'),
(12, 'Roley Kloska', '15 Thackeray Hill', '86249231', 'rkloskab@blogspot.com'),
(13, 'Farra Gloster', '69504 Almo Lane', '94520220', 'fglosterc@scientificamerican.com'),
(14, 'Aindrea Ondra', '84452 Welch Way', '67117935', 'aondrad@newyorker.com'),
(15, 'Judye Yuill', '8664 Vernon Parkway', '93291036', 'jyuille@angelfire.com'),
(16, 'Florette Mooney', '3762 Prentice Place', '95526053', 'fmooneyf@ezinearticles.com'),
(17, 'Lin Klimkov', '038 Grasskamp Circle', '96539717', 'lklimkovg@lulu.com'),
(18, 'Maddie Burder', '36116 Dunning Circle', '86301693', 'mburderh@columbia.edu'),
(19, 'Everett Cheeld', '663 Debs Way', '86130285', 'echeeldi@netvibes.com'),
(20, 'Jenna Dibsdale', '2717 Valley Edge Place', '89947731', 'jdibsdalej@google.pl'),
(21, 'Temple Wason', '56 Messerschmidt Park', '93511694', 'twasonk@wikia.com'),
(22, 'Maxine Burkill', '77956 Holmberg Drive', '87746095', 'mburkilll@webnode.com'),
(23, 'Cally O''Loghlen', '20 Stone Corner Place', '95973805', 'cologhlenm@comsenz.com'),
(24, 'Ertha Raddin', '7 Lake View Center', '97534238', 'eraddinn@fotki.com'),
(25, 'Cherilyn Hudspith', '7 Fairview Drive', '92381478', 'chudspitho@infoseek.co.jp'),
(26, 'Thurston Ockleshaw', '80476 Cherokee Road', '69931462', 'tockleshawp@ebay.com'),
(27, 'Annora Tanzig', '56406 Derek Alley', '82805095', 'atanzigq@e-recht24.de'),
(28, 'Lester Rouf', '5049 Hooker Parkway', '83788734', 'lroufr@mozilla.com'),
(29, 'Pate Downing', '47519 John Wall Park', '98259212', 'pdownings@oracle.com'),
(30, 'Cynthie Olanda', '69858 Forster Way', '88219924', 'colandat@sina.com.cn'),
(31, 'Leoline Hearst', '12142 Corry Center', '63669460', 'lhearstu@patch.com'),
(32, 'Nicole Cotgrove', '00 Calypso Way', '93380520', 'ncotgrovev@smugmug.com'),
(33, 'Shara Trevers', '126 Dwight Street', '97373319', 'streversw@slashdot.org'),
(34, 'Andrea Muckle', '82 Westend Drive', '96419019', 'amucklex@mapy.cz'),
(35, 'Giana Gaize', '29187 Sunbrook Place', '98077212', 'ggaizey@yahoo.co.jp'),
(36, 'Weylin Folkerd', '66292 Mendota Circle', '97184591', 'wfolkerdz@typepad.com'),
(37, 'Darbee Emanuelli', '06113 Ohio Pass', '99249447', 'demanuelli10@independent.co.uk'),
(38, 'Joanie Le Guin', '24 Sunnyside Terrace', '91525087', 'jle11@japanpost.jp'),
(39, 'Derick Janeczek', '9 Victoria Avenue', '64566685', 'djaneczek12@ask.com'),
(40, 'Jonah Dixey', '9 Vahlen Parkway', '94802005', 'jdixey13@liveinternet.ru');


INSERT INTO Credit_cards (card_number, CVV, expiry_date, from_date, cust_id) VALUES
('5578550114063345', '294', '12/17/2021', '08/26/2020', 1), 
('349448959736043', '870', '01/09/2024', '02/10/2020', 2), 
('5413117284994490', '431', '12/15/2023', '02/29/2020', 3), 
('5306212867742703', '397', '09/29/2025', '04/09/2020', 4), 
('349761782091745', '634', '12/18/2024', '01/04/2020', 5), 
('4929850819307', '325', '06/12/2023', '07/16/2020', 6), 
('4929488702248', '231', '11/22/2022', '12/06/2020', 7), 
('5197016788131579', '640', '05/25/2022', '05/10/2020', 8), 
('4928242194523600', '742', '04/20/2021', '06/11/2020', 9), 
('4485402183541709', '935', '07/10/2025', '10/23/2020', 10), 
('372955004953043', '352', '12/13/2025', '01/16/2021', 11), 
('4024007126727261', '875', '12/04/2021', '12/19/2020', 12), 
('4532897581102', '326', '03/12/2023', '03/21/2021', 13), 
('5428235772773391', '756', '10/17/2022', '06/19/2020', 14), 
('5108002499851380', '239', '08/28/2021', '06/26/2020', 15), 
('347108244342047', '937', '09/24/2024', '07/17/2020', 16), 
('5312064734949348', '339', '12/26/2021', '11/21/2020', 17), 
('4556436530884440', '852', '10/31/2025', '03/01/2021', 18), 
('5352506507527363', '363', '10/17/2025', '08/09/2020', 19), 
('375375413229926', '867', '12/02/2021', '11/18/2020', 20), 
('4916449362755054', '443', '10/07/2022', '10/13/2020', 21), 
('349169348983092', '113', '07/17/2023', '09/18/2020', 22), 
('4556358666177', '590', '12/26/2022', '12/15/2020', 23), 
('5460971818769683', '346', '03/06/2022', '05/04/2020', 24), 
('4539843895955149', '573', '06/13/2024', '02/12/2021', 25), 
('4556511091259883', '670', '11/27/2024', '07/24/2020', 26), 
('4585405913043', '478', '04/25/2024', '02/21/2021', 27), 
('4716875766872', '557', '06/20/2022', '03/26/2021', 28), 
('4024007117406404', '202', '10/01/2021', '08/16/2020', 29), 
('4532671887516612', '155', '09/18/2025', '08/16/2020', 30), 
('4873540841026', '615', '02/12/2025', '11/01/2020', 31), 
('370241251789675', '888', '05/02/2021', '03/06/2021', 32), 
('342555693345068', '422', '07/01/2022', '06/13/2020', 33), 
('5432829227817268', '617', '04/21/2023', '11/12/2020', 34), 
('5537078666197444', '828', '07/28/2022', '05/10/2020', 35), 
('5170242902744128', '765', '11/24/2021', '12/02/2020', 36), 
('5201362264241209', '393', '11/11/2023', '03/21/2020', 37), 
('4532518047533', '147', '09/03/2023', '01/25/2020', 38), 
('5542496535946259', '467', '02/19/2023', '03/02/2021', 39), 
('4716093432836', '752', '10/29/2021', '04/01/2020', 40);


/******************************
 * Purchase-related Information
 ******************************/

INSERT INTO Course_packages (package_id, name, num_free_registrations, price, sale_start_date, sale_end_date)
VALUES
(1, 'Cardify Package', 7, 777.99, '2/12/2021', '3/30/2021'), 
(2, 'Tresom Package', 8, 830.40, '12/22/2020', '2/4/2021'), 
(3, 'Wrapsafe Package', 6, 700, '2/14/2021', '3/28/2021'), 
(4, 'Y-find Package', 10, 1120.00, '12/26/2020', '2/9/2021'), 
(5, 'Pannier Package', 1, 119.95, '3/10/2021', '4/16/2021'), 
(6, 'It Package', 6, 710.00, '3/15/2021', '5/7/2021'), 
(7, 'Fixflex Package', 10, 1191.70, '12/24/2020', '1/20/2021'), 
(8, 'Bigtax Package', 6, 706.5, '3/30/2021', '4/26/2021'), 
(9, 'Transcof Package', 8, 946.88, '12/8/2020', '2/6/2021'), 
(10, 'Alpha Package', 10, 1195.4, '1/11/2021', '2/22/2021'), 
(11, 'Hatity Package', 7, 846.86, '1/15/2021', '2/15/2021'), 
(12, 'Span Package', 2, 245.62, '3/25/2021', '4/20/2021'), 
(13, 'Andalax Package', 6, 705.84, '12/15/2020', '1/10/2021'), 
(14, 'Trippledex Package', 2, 235.58, '1/17/2021', '3/16/2021'), 
(15, 'Greenlam Package', 7, 840.49, '12/12/2020', '1/27/2021'), 
(16, 'Hatity Package', 1, 122.88, '3/16/2021', '5/7/2021'), 
(17, 'Zontrax Package', 10, 1189.2, '2/13/2021', '3/13/2021'), 
(18, 'Konklux Package', 6, 697.08, '3/27/2021', '5/2/2021'), 
(19, 'Bitchip Package', 9, 1082.88, '3/7/2021', '4/20/2021'), 
(20, 'Zontrax Package', 2, 238.0, '1/3/2021', '2/18/2021'), 
(21, 'Pannier Package', 4, 492.12, '12/12/2020', '1/2/2021'), 
(22, 'Voyatouch Package', 10, 1179.3, '12/29/2020', '2/3/2021'), 
(23, 'Holdlamis Package', 10, 1158.5, '1/18/2021', '3/9/2021'), 
(24, 'Daltfresh Package', 2, 245.62, '12/17/2020', '1/17/2021'), 
(25, 'Holdlamis Package', 5, 576.7, '2/18/2021', '4/10/2021'), 
(26, 'Sonsing Package', 10, 1168.5, '1/4/2021', '2/22/2021'), 
(27, 'Regrant Package', 3, 371.19, '3/20/2021', '4/30/2021'), 
(28, 'Zoolab Package', 8, 944.32, '4/1/2021', '5/6/2021'), 
(29, 'Opela Package', 6, 704.76, '4/1/2021', '4/29/2021'), 
(30, 'Zoolab Package', 8, 981.2, '3/18/2021', '4/20/2021'), 
(31, 'Redhold Package', 5, 587.8, '2/12/2021', '3/9/2021'), 
(32, 'Wrapsafe Package', 4, 481.36, '1/16/2021', '3/15/2021'), 
(33, 'Keylex Package', 8, 951.04, '1/26/2021', '2/15/2021'), 
(34, 'Pannier Package', 2, 237.66, '12/29/2020', '2/11/2021'), 
(35, 'Aerified Package', 5, 602.7, '2/25/2021', '4/17/2021'), 
(36, 'Mat Lam Tam Package', 9, 1098.36, '2/11/2021', '3/3/2021'), 
(37, 'Otcom Package', 9, 1062.99, '2/4/2021', '3/25/2021'), 
(38, 'Matsoft Package', 3, 362.79, '1/27/2021', '3/26/2021'), 
(39, 'Zamit Package', 2, 233.42, '12/3/2020', '12/27/2020'), 
(40, 'Transcof Package', 10, 1185.0, '12/11/2020', '1/23/2021');


/**
 * TODO: Buys, Redeems, Registers and Cancels data generation not done (Not critical)
 */
insert into registers values ('2020-12-15', 2, 349448959736043, 1, '2020-11-16', 5224);
END;
