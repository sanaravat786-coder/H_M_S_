import React from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { LayoutDashboard, Users, BedDouble, CircleDollarSign, UserCheck, Wrench, FileText, X } from 'lucide-react';
import Logo from '../ui/Logo';

const adminNavLinks = [
    { icon: <LayoutDashboard />, text: 'Dashboard', path: '/' },
    { icon: <Users />, text: 'Students', path: '/students' },
    { icon: <BedDouble />, text: 'Rooms', path: '/rooms' },
    { icon: <CircleDollarSign />, text: 'Fees', path: '/fees' },
    { icon: <UserCheck />, text: 'Visitors', path: '/visitors' },
    { icon: <Wrench />, text: 'Maintenance', path: '/maintenance' },
    { icon: <FileText />, text: 'Reports', path: '/reports' },
];

const studentNavLinks = [
    { icon: <LayoutDashboard />, text: 'Dashboard', path: '/' },
    { icon: <BedDouble />, text: 'My Room', path: '/rooms' },
    { icon: <CircleDollarSign />, text: 'My Fees', path: '/fees' },
    { icon: <UserCheck />, text: 'My Visitors', path: '/visitors' },
    { icon: <Wrench />, text: 'Maintenance', path: '/maintenance' },
];

const staffNavLinks = [
    { icon: <LayoutDashboard />, text: 'Dashboard', path: '/' },
    { icon: <UserCheck />, text: 'Visitors', path: '/visitors' },
    { icon: <Wrench />, text: 'Maintenance', path: '/maintenance' },
];

const NavItem = ({ link, setSidebarOpen }) => (
    <NavLink
        to={link.path}
        end={link.path === '/'}
        onClick={() => setSidebarOpen(false)}
        className={({ isActive }) =>
            `flex items-center px-4 py-2.5 my-1 text-base-content-secondary dark:text-dark-base-content-secondary transition-colors duration-200 transform rounded-lg hover:bg-base-200 dark:hover:bg-dark-base-300 hover:text-base-content dark:hover:text-dark-base-content relative ${
                isActive ? 'bg-primary/10 dark:bg-dark-primary/20 text-primary dark:text-dark-primary font-semibold' : ''
            }`
        }
    >
        {React.cloneElement(link.icon, { className: 'w-5 h-5' })}
        <span className="mx-4 font-medium">{link.text}</span>
    </NavLink>
);

const Sidebar = ({ sidebarOpen, setSidebarOpen }) => {
    const { user } = useAuth();
    const role = user?.user_metadata?.role;

    let navLinks = [];
    if (role === 'Admin') {
        navLinks = adminNavLinks;
    } else if (role === 'Student') {
        navLinks = studentNavLinks; // Corrected: Student gets student links
    } else if (role === 'Staff') {
        navLinks = staffNavLinks; // Corrected: Staff gets staff links
    }

    return (
        <>
            <div className={`fixed inset-0 z-30 bg-black bg-opacity-50 transition-opacity lg:hidden ${sidebarOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`} onClick={() => setSidebarOpen(false)}></div>
            <div className={`transform top-0 left-0 w-64 bg-base-100/80 dark:bg-dark-base-200/80 backdrop-blur-lg fixed h-full overflow-auto ease-in-out transition-all duration-300 z-40 lg:translate-x-0 lg:static lg:inset-0 border-r border-base-300/50 dark:border-dark-base-300/50 ${ sidebarOpen ? 'translate-x-0' : '-translate-x-full'}`}>
                <div className="flex items-center justify-between px-6 py-4 border-b border-base-300/50 dark:border-dark-base-300/50">
                    <Logo className="text-primary dark:text-dark-primary" />
                     <button className="lg:hidden text-base-content-secondary dark:text-dark-base-content-secondary" onClick={() => setSidebarOpen(false)}>
                        <X className="w-6 h-6" />
                    </button>
                </div>
                <nav className="px-4 py-4">
                    {navLinks.map((link) => (
                        <NavItem key={link.path} link={link} setSidebarOpen={setSidebarOpen} />
                    ))}
                </nav>
            </div>
        </>
    );
};

export default Sidebar;
