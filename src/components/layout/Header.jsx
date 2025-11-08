import React from 'react';
import { Menu, LogOut } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { supabase } from '../../lib/supabase';
import toast from 'react-hot-toast';
import ThemeToggle from '../ui/ThemeToggle';
import UserAvatar from '../ui/UserAvatar';
import GlobalSearch from '../search/GlobalSearch';

const Header = ({ setSidebarOpen }) => {
    const { user } = useAuth();
    const navigate = useNavigate();

    const handleLogout = async () => {
        const { error } = await supabase.auth.signOut();
        if (error) {
            toast.error('Failed to log out.');
        } else {
            toast.success('Logged out successfully.');
            navigate('/login');
        }
    };

    return (
        <header className="sticky top-0 grid grid-cols-3 items-center px-6 py-3 bg-base-100/80 dark:bg-dark-base-200/80 backdrop-blur-lg border-b border-base-300/50 dark:border-dark-base-300/50 transition-colors z-30">
            {/* Left side */}
            <div className="flex items-center justify-start">
                <button onClick={() => setSidebarOpen(true)} className="text-base-content-secondary dark:text-dark-base-content-secondary focus:outline-none lg:hidden">
                    <Menu className="h-6 w-6" />
                </button>
            </div>

            {/* Middle */}
            <div className="flex justify-center">
                <GlobalSearch />
            </div>

            {/* Right side */}
            <div className="flex items-center justify-end space-x-2 sm:space-x-4">
                <ThemeToggle />
                <div className="relative flex items-center space-x-3">
                    <UserAvatar user={user} />
                    <button
                        onClick={handleLogout}
                        className="p-2 rounded-full text-base-content-secondary hover:text-base-content hover:bg-base-200 dark:text-dark-base-content-secondary dark:hover:text-dark-base-content dark:hover:bg-dark-base-300 transition-colors"
                        aria-label="Logout"
                    >
                        <LogOut className="h-5 w-5" />
                    </button>
                </div>
            </div>
        </header>
    );
};

export default Header;
