import React from 'react';
import { useTheme } from '../../context/ThemeContext';
import { Sun, Moon } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

const ThemeToggle = () => {
    const { theme, toggleTheme } = useTheme();

    return (
        <button
            onClick={toggleTheme}
            className="w-10 h-10 bg-base-200 dark:bg-dark-base-300 rounded-full flex items-center justify-center text-base-content-secondary dark:text-dark-base-content-secondary hover:bg-base-300 dark:hover:bg-dark-base-300/70 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary focus:ring-offset-base-100 dark:focus:ring-offset-dark-base-200 transition-colors"
            aria-label="Toggle theme"
        >
            <AnimatePresence mode="wait" initial={false}>
                <motion.div
                    key={theme}
                    initial={{ y: -20, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    exit={{ y: 20, opacity: 0 }}
                    transition={{ duration: 0.2 }}
                >
                    {theme === 'light' ? <Moon size={20} /> : <Sun size={20} />}
                </motion.div>
            </AnimatePresence>
        </button>
    );
};

export default ThemeToggle;
