import React from 'react';

const EmptyState = ({ icon, title, message }) => {
    return (
        <div className="text-center py-16 px-6">
            <div className="mx-auto h-12 w-12 text-base-content-secondary/50 dark:text-dark-base-content-secondary/50">{icon}</div>
            <h3 className="mt-4 text-lg font-semibold text-base-content dark:text-dark-base-content">{title}</h3>
            <p className="mt-1 text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{message}</p>
        </div>
    );
};

export default EmptyState;
