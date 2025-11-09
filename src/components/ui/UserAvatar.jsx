import React from 'react';
import { Link } from 'react-router-dom';

const UserAvatar = ({ user }) => {
    const getInitials = (name) => {
        if (!name) return '?';
        const names = name.split(' ');
        if (names.length > 1) {
            return `${names[0][0]}${names[names.length - 1][0]}`.toUpperCase();
        }
        return name.substring(0, 2).toUpperCase();
    };

    const fullName = user?.user_metadata?.full_name || user?.email;
    const initials = getInitials(fullName);

    return (
        <Link to="/profile" className="flex items-center space-x-3 group">
            <div className="w-10 h-10 flex items-center justify-center rounded-full bg-primary/20 dark:bg-dark-primary/30 text-primary dark:text-dark-primary font-bold group-hover:ring-2 group-hover:ring-primary dark:group-hover:ring-dark-primary transition-all">
                {initials}
            </div>
            <div className="hidden sm:block">
                <div className="text-sm font-semibold text-base-content dark:text-dark-base-content group-hover:text-primary dark:group-hover:text-dark-primary transition-colors">{fullName}</div>
                <div className="text-xs text-base-content-secondary dark:text-dark-base-content-secondary">{user?.user_metadata?.role}</div>
            </div>
        </Link>
    );
};

export default UserAvatar;
