import React from 'react';
import { Plus } from 'lucide-react';
import { motion } from 'framer-motion';

const PageHeader = ({ title, buttonText, onButtonClick }) => {
    return (
        <div className="flex items-center justify-between mb-8">
            <h1 className="text-4xl font-bold font-heading text-base-content dark:text-dark-base-content">{title}</h1>
            {buttonText && onButtonClick && (
                 <motion.button
                    onClick={onButtonClick}
                    className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-primary-content bg-primary hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary dark:bg-dark-primary dark:hover:bg-dark-primary-focus dark:text-dark-primary-content dark:focus:ring-dark-primary dark:focus:ring-offset-dark-base-100 transition-colors"
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                >
                    <Plus className="h-5 w-5 mr-2" />
                    {buttonText}
                </motion.button>
            )}
        </div>
    );
};

export default PageHeader;
