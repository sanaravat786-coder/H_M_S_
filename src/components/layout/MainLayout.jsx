import React, { useState } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import Sidebar from './Sidebar';
import Header from './Header';
import { AnimatePresence, motion } from 'framer-motion';

const pageVariants = {
    initial: {
        opacity: 0,
        x: "-5vw",
    },
    in: {
        opacity: 1,
        x: 0,
    },
    out: {
        opacity: 0,
        x: "5vw",
    }
};

const pageTransition = {
    type: "tween",
    ease: "anticipate",
    duration: 0.4
};

const MainLayout = () => {
    const [sidebarOpen, setSidebarOpen] = useState(false);
    const location = useLocation();

    return (
        <div className="flex h-screen bg-base-200 dark:bg-dark-base-100 font-sans transition-colors">
            <Sidebar sidebarOpen={sidebarOpen} setSidebarOpen={setSidebarOpen} />
            <div className="flex-1 flex flex-col overflow-hidden">
                <Header setSidebarOpen={setSidebarOpen} />
                <main className="flex-1 overflow-x-hidden overflow-y-auto">
                    <AnimatePresence mode="wait">
                        <motion.div 
                            key={location.pathname} 
                            className="container mx-auto px-6 py-8"
                            initial="initial"
                            animate="in"
                            exit="out"
                            variants={pageVariants}
                            transition={pageTransition}
                        >
                            <Outlet />
                        </motion.div>
                    </AnimatePresence>
                </main>
            </div>
        </div>
    );
};

export default MainLayout;
