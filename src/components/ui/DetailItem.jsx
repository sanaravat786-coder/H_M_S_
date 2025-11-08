import React from 'react';

const DetailItem = ({ label, value, children }) => {
    return (
        <div className="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt className="text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">{label}</dt>
            <dd className="mt-1 text-sm text-base-content dark:text-dark-base-content sm:mt-0 sm:col-span-2">{children || value}</dd>
        </div>
    );
};

export default DetailItem;
