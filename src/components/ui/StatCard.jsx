import React from 'react';
import { motion } from 'framer-motion';

const StatCard = ({ title, value, icon, color }) => {
    const cardVariants = {
        hidden: { opacity: 0, y: 20 },
        visible: { opacity: 1, y: 0, transition: { type: 'spring', stiffness: 100 } }
    };

    return (
        <motion.div 
            className="relative overflow-hidden bg-base-100 dark:bg-dark-base-200 rounded-2xl shadow-lg p-6 transition-all duration-300 transform hover:-translate-y-1"
            variants={cardVariants}
            whileHover={{ scale: 1.03 }}
        >
            <div className={`absolute -top-4 -right-4 w-24 h-24 rounded-full opacity-10 ${color}`}></div>
            <div className="relative z-10">
                <div className={`p-3 inline-block rounded-full mb-4 ${color}`}>
                    {React.cloneElement(icon, { className: 'h-6 w-6 text-white' })}
                </div>
                <p className="text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">{title}</p>
                <p className="text-3xl font-bold font-heading text-base-content dark:text-dark-base-content">{value}</p>
            </div>
        </motion.div>
    );
};

export default StatCard;
