import React from 'react';
import { Building2 } from 'lucide-react';

const Logo = ({ className }) => {
    return (
        <div className={`flex items-center font-heading font-bold text-2xl ${className}`}>
            <Building2 className="mr-2" />
            <span>HMS</span>
        </div>
    );
};

export default Logo;
