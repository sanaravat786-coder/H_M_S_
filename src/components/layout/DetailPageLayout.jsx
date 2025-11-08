import React from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

const DetailPageLayout = ({ title, children, backTo }) => {
    return (
        <>
            <div className="mb-6">
                <Link to={backTo} className="inline-flex items-center text-sm font-medium text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">
                    <ArrowLeft className="w-4 h-4 mr-2" />
                    Back to list
                </Link>
            </div>
            <h1 className="text-4xl font-bold font-heading text-base-content dark:text-dark-base-content mb-8">{title}</h1>
            <div className="bg-base-100 dark:bg-dark-base-200 p-6 sm:p-8 rounded-2xl shadow-lg transition-colors">
                <dl className="divide-y divide-base-200 dark:divide-dark-base-300">
                    {children}
                </dl>
            </div>
        </>
    );
};

export default DetailPageLayout;
