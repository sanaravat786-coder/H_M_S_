import React from 'react';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { Loader, Search } from 'lucide-react';

const resultVariants = {
    hidden: { opacity: 0, y: -10 },
    visible: { opacity: 1, y: 0, transition: { duration: 0.2 } },
};

const GroupHeader = ({ children }) => (
    <h4 className="px-4 pt-3 pb-2 text-xs font-semibold text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">
        {children}
    </h4>
);

const ResultItem = ({ item, onClick }) => (
    <Link
        to={item.path}
        onClick={onClick}
        className="block px-4 py-2.5 text-sm text-base-content dark:text-dark-base-content hover:bg-base-200 dark:hover:bg-dark-base-300 transition-colors"
    >
        {item.label}
    </Link>
);

const GlobalSearchResults = ({ results, loading, term, onClose }) => {
    const resultGroups = Object.entries(results || {}).filter(([, items]) => items.length > 0);
    const hasResults = resultGroups.length > 0;

    return (
        <motion.div
            variants={resultVariants}
            initial="hidden"
            animate="visible"
            exit="hidden"
            className="absolute top-full mt-2 w-full max-w-lg rounded-xl bg-base-100 dark:bg-dark-base-200 shadow-2xl overflow-hidden border border-base-300/50 dark:border-dark-base-300/50"
        >
            <div className="max-h-[60vh] overflow-y-auto">
                {loading && (
                    <div className="flex items-center justify-center p-16">
                        <Loader className="h-6 w-6 animate-spin text-primary" />
                    </div>
                )}
                {!loading && !hasResults && term && (
                    <div className="text-center p-16">
                        <Search className="mx-auto h-10 w-10 text-base-content-secondary/40" />
                        <p className="mt-4 font-semibold">No results for "{term}"</p>
                        <p className="text-sm text-base-content-secondary">Try searching for something else.</p>
                    </div>
                )}
                {!loading && hasResults && (
                    <>
                        {resultGroups.map(([groupName, items]) => (
                            <div key={groupName}>
                                <GroupHeader>{groupName}</GroupHeader>
                                <ul>
                                    {items.map(item => (
                                        <li key={`${groupName}-${item.id}`}>
                                            <ResultItem item={item} onClick={onClose} />
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        ))}
                    </>
                )}
            </div>
        </motion.div>
    );
};

export default GlobalSearchResults;
