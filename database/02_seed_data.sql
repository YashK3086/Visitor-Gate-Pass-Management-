-- ============================================================================
-- Corporate Visitor Gate Pass System (CVGPS) — Edge-Case Seed Data Matrix
-- File: database/02_seed_data.sql
-- Purpose: Populates realistic master data, visitor categories, parking zones,
--          and deterministic edge-case scenarios relative to NOW().
-- Version: 2.0 (Categories, Parking, Ex-Employees & Host Approvals)
-- ============================================================================

USE cvgps_pro;
SET NAMES utf8mb4;

-- ----------------------------------------------------------------------------
-- 1. Departments (7 departments; 'LEGAL' intentionally has 0 visits for LEFT JOIN analytics)
-- ----------------------------------------------------------------------------
INSERT INTO departments (dept_id, dept_code, dept_name, building_name, floor_no) VALUES
(1, 'ENG-CORE', 'Core Platform Engineering',     'Tower A - Nexus',    4),
(2, 'SEC-OPS',  'Cyber & Physical Security Ops', 'Tower A - Nexus',    1),
(3, 'AI-RES',   'Applied AI & Data Science',     'Tower B - Horizon',  6),
(4, 'FIN-TRE',  'Corporate Finance & Treasury',  'Tower B - Horizon',  2),
(5, 'PEOPLE',   'People Operations & Talent',    'Tower C - Atrium',   1),
(6, 'FAC-MGT',  'Facilities & Vendor Logistics', 'Service Annex',      0),
(7, 'LEGAL',    'Corporate Legal & Compliance',  'Tower B - Horizon',  8);

-- ----------------------------------------------------------------------------
-- 2. Shifts & Security Guards (guard_id = 6 is INACTIVE to test Errno 50008)
-- ----------------------------------------------------------------------------
INSERT INTO shifts (shift_id, shift_code, shift_name, start_time, end_time) VALUES
(1, 'MORNING', 'Alpha Morning Shift', '06:00:00', '14:00:00'),
(2, 'DAY',     'Bravo Day Shift',     '14:00:00', '22:00:00'),
(3, 'NIGHT',   'Charlie Night Shift', '22:00:00', '06:00:00');

INSERT INTO security_guards (guard_id, badge_no, first_name, last_name, phone, shift_id, is_active) VALUES
(1, 'SG-101', 'Rajesh',   'Chauhan', '+919820020001', 1, 1),
(2, 'SG-102', 'Mahesh',   'Yadav',   '+919820020002', 1, 1),
(3, 'SG-201', 'Sunita',   'Shinde',  '+919820020003', 2, 1),
(4, 'SG-202', 'Dinesh',   'Thakur',  '+919820020004', 2, 1),
(5, 'SG-301', 'Prakash',  'Rawat',   '+919820020005', 3, 1),
(6, 'SG-999', 'Brijesh',  'Tiwari',  '+919820020006', 3, 0);

-- ----------------------------------------------------------------------------
-- 3. Gate Checkpoints (checkpoint_id = 5 is INACTIVE)
-- ----------------------------------------------------------------------------
INSERT INTO checkpoints (checkpoint_id, checkpoint_code, checkpoint_name, building_name, is_active) VALUES
(1, 'MAIN-GATE-1', 'Main Vehicular & Pedestrian Gate 1', 'Perimeter North',   1),
(2, 'TOWER-A-LBY', 'Tower A Nexus Turnstile Lobby',      'Tower A - Nexus',   1),
(3, 'TOWER-B-LBY', 'Tower B Horizon Security Desk',      'Tower B - Horizon', 1),
(4, 'SERVICE-BAY', 'Logistics & Vendor Loading Dock',    'Service Annex',     1),
(5, 'OLD-EAST-GT', 'Decommissioned East Turnstile',      'Perimeter East',    0);

-- ----------------------------------------------------------------------------
-- 4. Government ID Proof Types
-- ----------------------------------------------------------------------------
INSERT INTO id_proof_types (id_proof_type_id, type_code, type_label) VALUES
(1, 'AADHAAR',         'UIDAI Aadhaar Card'),
(2, 'PASSPORT',        'National Passport'),
(3, 'DRIVING_LICENSE', 'RTO Driving License'),
(4, 'PAN_CARD',        'Income Tax PAN Card');

-- ----------------------------------------------------------------------------
-- 5. Employees / Hosts (Includes active staff + ex-employees with exit_type)
-- ----------------------------------------------------------------------------
INSERT INTO employees (
    emp_id, emp_code, first_name, last_name, email, phone, dept_id, is_active,
    id_proof_type_id, id_proof_hash, id_proof_last4, exit_type, exit_date
) VALUES
(1,  'EMP-1001', 'Aarav',     'Mehta',      'aarav.mehta@cvgps-corp.in',     '+919810010001', 1, 1, 1, fn_hash_id_proof(1, '901234567890'), '7890', NULL, NULL),
(2,  'EMP-1002', 'Priya',     'Nair',       'priya.nair@cvgps-corp.in',      '+919810010002', 1, 1, 1, fn_hash_id_proof(1, '901234567891'), '7891', NULL, NULL),
(3,  'EMP-1003', 'Rohan',     'Kulkarni',   'rohan.kulkarni@cvgps-corp.in',  '+919810010003', 1, 1, 4, fn_hash_id_proof(4, 'ABCDE1111A'),   '111A', NULL, NULL),
(4,  'EMP-1004', 'Vikram',    'Rathore',    'vikram.rathore@cvgps-corp.in',  '+919810010004', 2, 1, 1, fn_hash_id_proof(1, '901234567892'), '7892', NULL, NULL),
(5,  'EMP-1005', 'Ananya',    'Sen',        'ananya.sen@cvgps-corp.in',      '+919810010005', 2, 1, 2, fn_hash_id_proof(2, 'K1122334'),     '2334', NULL, NULL),
(6,  'EMP-1006', 'Devika',    'Iyer',       'devika.iyer@cvgps-corp.in',     '+919810010006', 3, 1, 1, fn_hash_id_proof(1, '901234567893'), '7893', NULL, NULL),
(7,  'EMP-1007', 'Kabir',     'Bhatia',     'kabir.bhatia@cvgps-corp.in',    '+919810010007', 3, 1, 3, fn_hash_id_proof(3, 'DL0120190001'), '0001', NULL, NULL),
(8,  'EMP-1008', 'Siddharth', 'Menon',      'siddharth.menon@cvgps-corp.in', '+919810010008', 3, 1, 1, fn_hash_id_proof(1, '901234567894'), '7894', NULL, NULL),
(9,  'EMP-1009', 'Neha',      'Kapoor',     'neha.kapoor@cvgps-corp.in',     '+919810010009', 4, 1, 4, fn_hash_id_proof(4, 'ABCDE2222B'),   '222B', NULL, NULL),
(10, 'EMP-1010', 'Arjun',     'Malhotra',   'arjun.malhotra@cvgps-corp.in',  '+919810010010', 4, 1, 1, fn_hash_id_proof(1, '901234567895'), '7895', NULL, NULL),
(11, 'EMP-1011', 'Meera',     'Krishnan',   'meera.krishnan@cvgps-corp.in',  '+919810010011', 5, 1, 1, fn_hash_id_proof(1, '901234567896'), '7896', NULL, NULL),
(12, 'EMP-1012', 'Tanvi',     'Deshmukh',   'tanvi.deshmukh@cvgps-corp.in',  '+919810010012', 5, 1, 2, fn_hash_id_proof(2, 'L2233445'),     '3445', NULL, NULL),
(13, 'EMP-1013', 'Harsh',     'Vardhan',    'harsh.vardhan@cvgps-corp.in',   '+919810010013', 6, 1, 1, fn_hash_id_proof(1, '901234567897'), '7897', NULL, NULL),
(14, 'EMP-1014', 'Pooja',     'Chatterjee', 'pooja.chatterjee@cvgps-corp.in','+919810010014', 6, 1, 3, fn_hash_id_proof(3, 'MH0220200002'), '0002', NULL, NULL),
(15, 'EMP-1015', 'Nikhil',    'Saxena',     'nikhil.saxena@cvgps-corp.in',   '+919810010015', 7, 1, 4, fn_hash_id_proof(4, 'ABCDE3333C'),   '333C', NULL, NULL),
-- Ex-Employee 1: Suresh Pillai (Resigned amicably on 2026-08-15)
(16, 'EMP-1016', 'Suresh',    'Pillai',     'suresh.pillai@cvgps-corp.in',   '+919810010016', 1, 0, 1, fn_hash_id_proof(1, '662288114499'), '4499', 'RESIGNED', '2026-08-15'),
-- Ex-Employee 2: Tarun Kapoor (Terminated for cause on 2026-09-01)
(17, 'EMP-1017', 'Tarun',     'Kapoor',     'tarun.kapoor@cvgps-corp.in',    '+919810010017', 2, 0, 4, fn_hash_id_proof(4, 'EXEMP9999K'),   '999K', 'TERMINATED', '2026-09-01');

-- ----------------------------------------------------------------------------
-- 6. Visitor Categories & Policies
-- ----------------------------------------------------------------------------
INSERT INTO visitor_categories (
    category_id, category_code, category_name, max_pass_hours, parking_allowed,
    max_parking_minutes, requires_escort, requires_host_approval, allowed_from_time, allowed_to_time
) VALUES
(1,  'MEETING_GUEST',       'Client & Partner Business Meeting',          8,  1, 240, 0, 0, '06:00:00', '22:00:00'),
(2,  'INTERVIEW_CANDIDATE', 'Recruitment & Candidate Interview',          6,  1, 360, 0, 0, '08:00:00', '20:00:00'),
(3,  'CONTRACTOR',          'Contractor, Maintenance & Physical Repairs', 12, 1, 600, 0, 1, '06:00:00', '23:00:00'),
(4,  'NEW_JOINEE',          'New Employee Onboarding (Pre-HR Provision)', 12, 1, 720, 0, 0, '07:00:00', '21:00:00'),
(5,  'DELIVERY_COURIER',    'Dispatch, Parcel & Express Delivery',         2,  1, 20,  0, 0, '06:00:00', '22:00:00'),
(6,  'VENDOR_SUPPLIER',     'Vendor Logistics & Inventory Delivery',       8,  1, 180, 0, 0, '07:00:00', '20:00:00'),
(7,  'VIP_GUEST',           'Executive Board & Investor Delegations',     10, 1, 480, 1, 0, '06:00:00', '23:59:59'),
(8,  'GOVT_INSPECTOR',      'Regulatory, Fire & Labor Inspection',         8,  0, 0,   1, 1, '09:00:00', '18:00:00'),
(9,  'EX_EMPLOYEE',         'Ex-Employee Alumni, Settlement & HR Formal',  4,  1, 120, 0, 1, '09:00:00', '17:00:00'),
(10, 'EMERGENCY_SERVICES',  'First Responders, Fire & Medical Ambulance', 24, 1, 1440,0, 0, '00:00:00', '23:59:59');

-- ----------------------------------------------------------------------------
-- 7. Category Checkpoint Permissions
-- ----------------------------------------------------------------------------
-- Meeting Guests & Interviews: Main Gate, Tower A, Tower B
INSERT INTO category_checkpoints (category_id, checkpoint_id) VALUES
(1, 1), (1, 2), (1, 3),
(2, 1), (2, 2), (2, 3),
-- Contractors: Main Gate, Service Bay (cannot use tower lobbies)
(3, 1), (3, 4),
-- New Joinees: Main Gate, Tower A Lobby
(4, 1), (4, 2),
-- Couriers & Vendors: Main Gate, Service Bay
(5, 1), (5, 4),
(6, 1), (6, 4),
-- VIP: Main Gate, Tower A, Tower B
(7, 1), (7, 2), (7, 3),
-- Govt Inspector: Main Gate, Tower A, Tower B, Service Bay
(8, 1), (8, 2), (8, 3), (8, 4),
-- Ex-Employee: Main Gate, Tower A Lobby
(9, 1), (9, 2),
-- Emergency: All gates
(10, 1), (10, 2), (10, 3), (10, 4);

-- ----------------------------------------------------------------------------
-- 8. Parking Zones
-- ----------------------------------------------------------------------------
INSERT INTO parking_zones (zone_id, zone_code, zone_name, capacity, allowed_vehicle_types) VALUES
(1, 'VISITOR-P1',     'Visitor North Surface Lot (Bay A-C)',        25, 'SEDAN,SUV,TWO_WHEELER'),
(2, 'SERVICE-BAY',    'Logistics Loading Dock & Contractor Parking', 8, 'TRUCK,VAN,SEDAN,SUV'),
(3, 'VIP-VALET',      'Executive Portico Undercover Valet',         10, 'SEDAN,SUV'),
(4, 'TWO-WHEELER-P1', 'North Gate Motorcycle & Scooter Bay',        30, 'TWO_WHEELER');

-- ----------------------------------------------------------------------------
-- 9. Visitors (25 visitors; including ex-employees & new joinees)
-- ----------------------------------------------------------------------------
INSERT INTO visitors (
    visitor_id, first_name, last_name, phone, email, company_name,
    id_proof_type_id, id_proof_hash, id_proof_last4
) VALUES
(1,  'Aditi',     'Sharma',     '+919700010001', 'aditi.sharma@infosys-partner.com', 'Infosys Consulting',     1, fn_hash_id_proof(1, '482910384711'), '4711'),
(2,  'Rakesh',    'Verma',      '+919700010002', 'rakesh.verma@rogue-vendor.net',    'Unverified Contractors', 2, fn_hash_id_proof(2, 'Z8839201'),     '9201'),
(3,  'Karan',     'Oberoi',     '+919700010003', 'karan.oberoi@cloudscale.io',       'CloudScale Systems',     2, fn_hash_id_proof(2, 'P7748292'),     '8292'),
(4,  'Sanya',     'Malik',      '+919700010004', 'sanya.malik@deloitte-audit.com',   'Deloitte Risk Advisory', 4, fn_hash_id_proof(4, 'ABCDE1234F'),   '234F'),
(5,  'Deepak',    'Nambiar',    '+919700010005', 'deepak.nambiar@siemens-grid.com',  'Siemens Energy',         3, fn_hash_id_proof(3, 'KA0120198831'), '8831'),
(6,  'Nandini',   'Rao',        '+919700010006', 'nandini.rao@aws-india.com',        'Amazon Web Services',    1, fn_hash_id_proof(1, '673829104422'), '4422'),
(7,  'Gaurav',    'Bansal',     '+919700010007', 'gaurav.bansal@zomato-b2b.com',     'HyperPure Logistics',    3, fn_hash_id_proof(3, 'DL0420219920'), '9920'),
(8,  'Ishaan',    'Choudhary',  '+919700010008', 'ishaan.c@accenture-tech.com',      'Accenture Labs',         2, fn_hash_id_proof(2, 'M9920183'),     '0183'),
(9,  'Ritika',    'Jain',       '+919700010009', 'ritika.jain@kpmg-india.com',       'KPMG Assurance',         4, fn_hash_id_proof(4, 'PQRSX6789K'),   '789K'),
(10, 'Manish',    'Agarwal',    '+919700010010', 'manish.agarwal@cisco-net.com',     'Cisco Meraki',           1, fn_hash_id_proof(1, '991827364551'), '4551'),
(11, 'Shreya',    'Ghoshal',    '+919700010011', 'shreya.g@talentbridge.in',         'TalentBridge HR',        1, fn_hash_id_proof(1, '882736451920'), '1920'),
(12, 'Varun',     'Dhawan',     '+919700010012', 'varun.dhawan@hvac-cooling.in',     'BlueStar HVAC Services', 3, fn_hash_id_proof(3, 'MH1220187712'), '7712'),
(13, 'Nisha',     'Patel',      '+919700010013', 'nisha.patel@stripe-pay.com',       'Stripe FinTech',         2, fn_hash_id_proof(2, 'N5541209'),     '1209'),
(14, 'Abhishek',  'Tripathi',   '+919700010014', NULL,                               'Independent Courier',    1, fn_hash_id_proof(1, '771625349811'), '9811'),
(15, 'Kavita',    'Desai',      '+919700010015', 'kavita.desai@pwc-advisory.com',    'PwC Tax & Treasury',     4, fn_hash_id_proof(4, 'LMNOP4321Q'),   '321Q'),
(16, 'Pranav',    'Mukherjee',  '+919700010016', 'pranav.m@nvidia-partner.com',      'NVIDIA DeepLearning',    2, fn_hash_id_proof(2, 'V3301928'),     '1928'),
-- Visitor #17: Suresh Pillai (Ex-Employee, Resigned amicably, matches emp #16)
(17, 'Suresh',    'Pillai',     '+919810010016', 'suresh.pillai@gmail.com',          'Ex-Employee Alumni',     1, fn_hash_id_proof(1, '662288114499'), '4499'),
-- Visitor #18: Tarun Kapoor (Ex-Employee, Terminated for cause, matches emp #17)
(18, 'Tarun',     'Kapoor',     '+919810010017', 'tarun.k@yahoo.com',                'Former Staff',           4, fn_hash_id_proof(4, 'EXEMP9999K'),   '999K'),
(19, 'Swati',     'Bose',       '+919700010019', 'swati.bose@gartner-research.com',  'Gartner Analysts',       2, fn_hash_id_proof(2, 'G4491827'),     '1827'),
(20, 'Rajat',     'Srivastava', '+919700010020', 'rajat.s@ey-cyber.com',             'EY Cyber Forensics',     4, fn_hash_id_proof(4, 'ZYXWV9876A'),   '876A'),
-- Visitor #21: Rahul Verma (New Joinee onboarding today)
(21, 'Rahul',     'Verma',      '+919700010021', 'rahul.verma.joinee@gmail.com',     'CVGPS Engineering Joinee',1, fn_hash_id_proof(1, '119922883377'), '3377'),
-- Visitor #22: Manoj Kumar (Courier)
(22, 'Manoj',     'Kumar',      '+919700010022', NULL,                               'BlueDart Express Courier', 3, fn_hash_id_proof(3, 'DL0120224411'), '4411'),
-- Visitor #23: Amit Sharma (Contractor - Plumber / HVAC)
(23, 'Amit',      'Sharma',     '+919700010023', 'amit.repairs@urbanfacility.in',    'Urban Facilities & Repair', 1, fn_hash_id_proof(1, '883344112200'), '2200'),
(24, 'Pallavi',   'Joshi',      '+919700010024', 'pallavi.joshi@workday-hr.com',     'Workday Implementation', 1, fn_hash_id_proof(1, '223344556677'), '6677'),
(25, 'Naveen',    'Jindal',     '+919700010025', 'naveen.jindal@abb-robotics.com',   'ABB Industrial',         3, fn_hash_id_proof(3, 'GJ0120225566'), '5566');

-- ----------------------------------------------------------------------------
-- 10. Vehicles
-- ----------------------------------------------------------------------------
INSERT INTO vehicles (vehicle_id, visitor_id, registration_no, vehicle_type, make_model) VALUES
(1,  1,  'KA-01-MJ-4821', 'SEDAN',       'Honda City ZX'),
(2,  1,  'KA-05-NB-9012', 'SUV',         'Hyundai Creta SX'),
(3,  3,  'MH-12-DE-3344', 'SEDAN',       'Skoda Slavia'),
(4,  5,  'DL-03-CA-7788', 'SUV',         'Toyota Innova Hycross'),
(5,  6,  'KA-03-HA-1122', 'TWO_WHEELER', 'Ather 450X Electric'),
(6,  8,  'TN-09-BC-5566', 'SEDAN',       'Volkswagen Virtus'),
(7,  10, 'HR-26-DK-8899', 'SUV',         'Mahindra XUV700'),
(8,  12, 'MH-14-CV-2040', 'VAN',         'Tata Winger HVAC Service Van'),
(9,  16, 'KA-04-EN-6070', 'SEDAN',       'BYD Seal EV'),
(10, 18, 'DL-08-TR-4090', 'TRUCK',       'Eicher Pro 2049 Switchgear Carrier'),
(11, 21, 'KA-03-NJ-1020', 'SEDAN',       'Tata Nexon EV (New Joinee)'),
(12, 22, 'DL-01-CR-8833', 'TWO_WHEELER', 'Hero Splendor Courier Van'),
(13, 23, 'MH-04-RP-9922', 'VAN',         'Maruti Eeco Repair Van');

-- ----------------------------------------------------------------------------
-- 11. DETERMINISTIC EDGE-CASE PASSES
-- ----------------------------------------------------------------------------

-- Scenario #1: GP-DEMO01 — Happy-Path APPROVED pass, valid right now (Aditi Sharma, Vehicle #1, Meeting)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-DEMO01', 1, 1, 1, 1,
    'Q4 Platform Architecture Review & Database Sign-off',
    NOW() - INTERVAL 20 MINUTE,
    NOW() + INTERVAL 4 HOUR,
    'APPROVED',
    NOW() - INTERVAL 25 MINUTE
);

-- Scenario #2: GP-DEMO02 — Second APPROVED pass (Sanya Malik, Financial Audit)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-DEMO02', 4, 9, 1, NULL,
    'SOX & Internal Controls Financial Audit Walkthrough',
    NOW() - INTERVAL 15 MINUTE,
    NOW() + INTERVAL 3 HOUR,
    'APPROVED',
    NOW() - INTERVAL 20 MINUTE
);

-- Scenario #3: GP-BLKD01 — Pass APPROVED 30m ago for Karan Oberoi, THEN visitor blacklisted 10m ago
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-BLKD01', 3, 2, 1, 3,
    'Production Kubernetes Cluster Access Review',
    NOW() - INTERVAL 30 MINUTE,
    NOW() + INTERVAL 3 HOUR,
    'APPROVED',
    NOW() - INTERVAL 35 MINUTE
);

-- Scenario #4: GP-EXPD01 — Unused pass whose valid_until window passed 2 hours ago
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-EXPD01', 7, 13, 6, NULL,
    'Cafeteria Cold-Chain Vendor Inspection (Window Missed)',
    NOW() - INTERVAL 6 HOUR,
    NOW() - INTERVAL 2 HOUR,
    'APPROVED',
    NOW() - INTERVAL 6 HOUR
);

-- Scenario #5: GP-FUTR01 — Future pass (valid_from is 3 hours in the future)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-FUTR01', 11, 11, 2, NULL,
    'Executive Leadership Hiring Panel Briefing',
    NOW() + INTERVAL 3 HOUR,
    NOW() + INTERVAL 7 HOUR,
    'APPROVED',
    NOW() - INTERVAL 10 MINUTE
);

-- Scenario #6: GP-ONSIT1 — Currently ACTIVE_ON_CAMPUS within valid window (Ishaan Choudhary)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, created_at
) VALUES (
    'GP-ONSIT1', 8, 6, 1, 6,
    'LLM Inference Latency Benchmarking Workshop',
    NOW() - INTERVAL 90 MINUTE,
    NOW() + INTERVAL 150 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 75 MINUTE, 1, 2,
    NOW() - INTERVAL 100 MINUTE
);

-- Scenario #7: GP-ONSIT2 — Currently ACTIVE_ON_CAMPUS (Pranav Mukherjee)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, created_at
) VALUES (
    'GP-ONSIT2', 16, 7, 1, 9,
    'GPU Cluster Interconnect Commissioning',
    NOW() - INTERVAL 50 MINUTE,
    NOW() + INTERVAL 190 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 42 MINUTE, 2, 3,
    NOW() - INTERVAL 60 MINUTE
);

-- Scenario #8: GP-SOON01 — ACTIVE_ON_CAMPUS expiring in 10 minutes (Swati Bose)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, created_at
) VALUES (
    'GP-SOON01', 19, 4, 1, NULL,
    'Zero-Trust Network Architecture Analyst Briefing',
    NOW() - INTERVAL 170 MINUTE,
    NOW() + INTERVAL 10 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 160 MINUTE, 3, 2,
    NOW() - INTERVAL 175 MINUTE
);

-- Scenario #9: GP-OVER01 — ACTIVE_ON_CAMPUS but OVERSTAYING (valid_until expired 55 mins ago)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, is_overstay, created_at
) VALUES (
    'GP-OVER01', 10, 1, 1, 7,
    'Core Switch Firmware Upgrade & Testing',
    NOW() - INTERVAL 295 MINUTE,
    NOW() - INTERVAL 55 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 280 MINUTE, 1, 1, 1,
    NOW() - INTERVAL 300 MINUTE
);

-- Scenario #10: GP-APPR01 — PENDING_APPROVAL for Ex-Employee Suresh Pillai visiting HR
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-APPR01', 17, 11, 9, NULL,
    'Full & Final Settlement Documents & PF Transfer Clearance',
    NOW() - INTERVAL 10 MINUTE,
    NOW() + INTERVAL 3 HOUR,
    'PENDING_APPROVAL',
    NOW() - INTERVAL 15 MINUTE
);

-- Scenario #11: GP-APPR02 — PENDING_APPROVAL for Contractor Amit Sharma (HVAC plumbing repairs)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status, created_at
) VALUES (
    'GP-APPR02', 23, 13, 3, 13,
    'Server Room Chiller Line Emergency Leak Repair',
    NOW() - INTERVAL 5 MINUTE,
    NOW() + INTERVAL 8 HOUR,
    'PENDING_APPROVAL',
    NOW() - INTERVAL 10 MINUTE
);

-- Scenario #12: GP-PARK01 — ACTIVE_ON_CAMPUS New Joinee Rahul Verma with Active Parking in VISITOR-P1
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, created_at
) VALUES (
    'GP-PARK01', 21, 11, 4, 11,
    'First Day Engineering Onboarding & Badge Allocation',
    NOW() - INTERVAL 60 MINUTE,
    NOW() + INTERVAL 660 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 55 MINUTE, 1, 1,
    NOW() - INTERVAL 70 MINUTE
);

-- Scenario #13: GP-PKST01 — ACTIVE_ON_CAMPUS Courier Manoj Kumar OVERSTAYING in Parking (Limit: 20m, Parked: 45m)
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id, created_at
) VALUES (
    'GP-PKST01', 22, 13, 5, 12,
    'Urgent Server Replacement Parts Delivery to Annex',
    NOW() - INTERVAL 50 MINUTE,
    NOW() + INTERVAL 70 MINUTE,
    'ACTIVE_ON_CAMPUS',
    NOW() - INTERVAL 48 MINUTE, 1, 4,
    NOW() - INTERVAL 55 MINUTE
);

-- ----------------------------------------------------------------------------
-- 12. PARKING SESSIONS (Active sessions for GP-PARK01 and GP-PKST01)
-- ----------------------------------------------------------------------------
INSERT INTO parking_sessions (pass_id, vehicle_id, zone_id, allocated_minutes, entry_time, exit_time, is_overstay)
VALUES
-- Session 1: New joinee parked in VISITOR-P1 (allocated 720 mins, parked 50 mins ago -> NORMAL)
(
    (SELECT pass_id FROM gate_passes WHERE pass_code = 'GP-PARK01'),
    11, 1, 720, NOW() - INTERVAL 50 MINUTE, NULL, 0
),
-- Session 2: Courier parked in SERVICE-BAY (allocated 20 mins, parked 40 mins ago -> OVERSTAY)
(
    (SELECT pass_id FROM gate_passes WHERE pass_code = 'GP-PKST01'),
    12, 2, 20, NOW() - INTERVAL 40 MINUTE, NULL, 1
);

-- ----------------------------------------------------------------------------
-- 13. VISITOR BLACKLIST
-- ----------------------------------------------------------------------------
INSERT INTO visitor_blacklist (
    blacklist_id, visitor_id, reason, severity, start_at, end_at, lifted_at, lifted_reason, created_by
) VALUES
-- Rakesh Verma: Permanent critical blacklist
(1, 2,  'Aggressive altercation at North Gate checkpoint and forged contractor ID badge', 'CRITICAL', NOW() - INTERVAL 30 DAY, NULL, NULL, NULL, 1),
-- Karan Oberoi: High severity active blacklist
(2, 3,  'Unauthorized photography inside Core Server Room and refusal to surrender media', 'HIGH',     NOW() - INTERVAL 10 MINUTE, NOW() + INTERVAL 90 DAY, NULL, NULL, 2),
-- Deepak Nambiar: Expired temporal blacklist
(3, 5,  'Overdue safety briefing completion prior to sub-station access',                  'LOW',      NOW() - INTERVAL 60 DAY, NOW() - INTERVAL 10 DAY, NULL, NULL, 1),
-- Abhishek Tripathi: Lifted blacklist
(4, 14, 'Improper vehicle parking obstructing primary fire hydrant',                       'MEDIUM',   NOW() - INTERVAL 14 DAY, NULL, NOW() - INTERVAL 2 DAY, 'Driver completed mandatory campus safety training and vehicle fine settled.', 3);

-- ----------------------------------------------------------------------------
-- 14. HISTORICAL COMPLETED PASSES (for analytics & window function demonstration)
-- ----------------------------------------------------------------------------
INSERT INTO gate_passes (
    pass_code, visitor_id, host_emp_id, category_id, vehicle_id, visit_purpose,
    valid_from, valid_until, status,
    check_in_time, check_in_guard_id, check_in_checkpoint_id,
    check_out_time, check_out_guard_id, check_out_checkpoint_id,
    is_overstay, created_at
) VALUES
('GP-HIST01', 5, 1, 1, 4, 'Electrical Substation SCADA Calibration',
 NOW() - INTERVAL 2 DAY - INTERVAL 4 HOUR, NOW() - INTERVAL 2 DAY, 'COMPLETED',
 NOW() - INTERVAL 2 DAY - INTERVAL 230 MINUTE, 1, 1,
 NOW() - INTERVAL 2 DAY - INTERVAL 30 MINUTE,  1, 1, 0, NOW() - INTERVAL 2 DAY - INTERVAL 5 HOUR),

('GP-HIST02', 6, 2, 1, 5, 'DirectConnect 100G Fiber Link Commissioning',
 NOW() - INTERVAL 1 DAY - INTERVAL 6 HOUR, NOW() - INTERVAL 1 DAY - INTERVAL 2 HOUR, 'COMPLETED',
 NOW() - INTERVAL 1 DAY - INTERVAL 350 MINUTE, 2, 2,
 NOW() - INTERVAL 1 DAY - INTERVAL 110 MINUTE, 2, 2, 1, NOW() - INTERVAL 1 DAY - INTERVAL 7 HOUR),

('GP-HIST03', 9, 9, 1, NULL, 'External Financial Audit Working Papers Review',
 NOW() - INTERVAL 3 DAY - INTERVAL 5 HOUR, NOW() - INTERVAL 3 DAY - INTERVAL 1 HOUR, 'COMPLETED',
 NOW() - INTERVAL 3 DAY - INTERVAL 280 MINUTE, 3, 3,
 NOW() - INTERVAL 3 DAY - INTERVAL 80 MINUTE,  3, 3, 0, NOW() - INTERVAL 3 DAY - INTERVAL 6 HOUR),

('GP-HIST04', 12, 13, 3, 8, 'HVAC Chiller Compressor Scheduled Overhaul',
 NOW() - INTERVAL 4 DAY - INTERVAL 8 HOUR, NOW() - INTERVAL 4 DAY - INTERVAL 2 HOUR, 'COMPLETED',
 NOW() - INTERVAL 4 DAY - INTERVAL 450 MINUTE, 1, 4,
 NOW() - INTERVAL 4 DAY - INTERVAL 130 MINUTE, 1, 4, 0, NOW() - INTERVAL 4 DAY - INTERVAL 9 HOUR),

('GP-HIST05', 13, 10, 1, NULL, 'Stripe Merchant Gateway Integration Strategy',
 NOW() - INTERVAL 5 DAY - INTERVAL 3 HOUR, NOW() - INTERVAL 5 DAY, 'COMPLETED',
 NOW() - INTERVAL 5 DAY - INTERVAL 170 MINUTE, 4, 3,
 NOW() - INTERVAL 5 DAY - INTERVAL 20 MINUTE,  4, 3, 0, NOW() - INTERVAL 5 DAY - INTERVAL 4 HOUR),

('GP-HIST06', 15, 10, 1, NULL, 'Transfer Pricing & Cross-Border Tax Briefing',
 NOW() - INTERVAL 1 DAY - INTERVAL 4 HOUR, NOW() - INTERVAL 1 DAY - INTERVAL 1 HOUR, 'COMPLETED',
 NOW() - INTERVAL 1 DAY - INTERVAL 230 MINUTE, 1, 1,
 NOW() - INTERVAL 1 DAY - INTERVAL 50 MINUTE,  1, 1, 0, NOW() - INTERVAL 1 DAY - INTERVAL 5 HOUR);

ANALYZE TABLE gate_passes, access_audit_logs, visitors, employees, departments, visitor_categories, parking_zones, parking_sessions;
