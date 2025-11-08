import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X } from 'lucide-react';

const Modal = ({ isOpen, onClose, title, children }) => {
    return (
        <AnimatePresence>
            {isOpen && (
                <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
                    onClick={onClose}
                >
                    <motion.div
                        initial={{ scale: 0.9, opacity: 0, y: -30 }}
                        animate={{ scale: 1, opacity: 1, y: 0 }}
                        exit={{ scale: 0.9, opacity: 0, y: -30 }}
                        transition={{ type: 'spring', stiffness: 300, damping: 30 }}
                        className="bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-2xl w-full max-w-lg m-4"
                        onClick={(e) => e.stopPropagation()}
                    >
                        <div className="flex items-center justify-between p-5 border-b border-base-200 dark:border-dark-base-300">
                            <h3 className="text-xl font-semibold text-base-content dark:text-dark-base-content">{title}</h3>
                            <button
                                onClick={onClose}
                                className="text-base-content-secondary hover:text-base-content dark:hover:text-dark-base-content"
                            >
                                <X className="w-6 h-6" />
                            </button>
                        </div>
                        <div className="p-6">
                            {children}
                        </div>
                    </motion.div>
                </motion.div>
            )}
        </AnimatePresence>
    );
};

export default Modal;
