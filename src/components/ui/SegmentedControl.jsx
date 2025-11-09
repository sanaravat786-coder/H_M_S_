import React from 'react';
import { motion } from 'framer-motion';

const SegmentedControl = ({ options, value, onChange, size = 'sm' }) => {
    const sizeClasses = {
        sm: 'px-2.5 py-1 text-xs',
        md: 'px-3 py-1.5 text-sm',
    };

    return (
        <div className="flex items-center space-x-1 bg-base-200 dark:bg-dark-base-300 rounded-lg p-1">
            {options.map(option => (
                <button
                    key={option.value}
                    onClick={() => onChange(option.value)}
                    className={`relative w-full rounded-md transition-colors ${sizeClasses[size]} ${value === option.value ? 'text-base-content dark:text-dark-base-content' : 'text-base-content-secondary dark:text-dark-base-content-secondary hover:text-base-content dark:hover:text-dark-base-content'}`}
                >
                    {value === option.value && (
                        <motion.div
                            layoutId="segmented-control-active"
                            className="absolute inset-0 bg-base-100 dark:bg-dark-base-200 rounded-md shadow-sm"
                            transition={{ type: 'spring', stiffness: 300, damping: 30 }}
                        />
                    )}
                    <span className="relative z-10">{option.label}</span>
                </button>
            ))}
        </div>
    );
};

export default SegmentedControl;
