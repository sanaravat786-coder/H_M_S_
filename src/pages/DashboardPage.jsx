import React from 'react';
import { useAuth } from '../context/AuthContext';
import { Loader } from 'lucide-react';
import AdminDashboard from '../components/dashboard/AdminDashboard';
import StudentDashboard from '../components/dashboard/StudentDashboard';

const DashboardPage = () => {
    const { user, loading } = useAuth();

    if (loading) {
        return (
            <div className="flex justify-center items-center h-64">
                <Loader className="animate-spin h-8 w-8 text-primary" />
            </div>
        );
    }

    const role = user?.user_metadata?.role;

    if (role === 'Student') {
        return <StudentDashboard />;
    }

    if (role === 'Admin' || role === 'Staff') {
        return <AdminDashboard />;
    }

    return (
        <div className="text-center p-8 bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-lg">
            <h2 className="text-2xl font-bold">Role Not Assigned</h2>
            <p className="text-base-content-secondary dark:text-dark-base-content-secondary mt-2">
                You do not have a role assigned to your account. Please contact an administrator for assistance.
            </p>
        </div>
    );
};

export default DashboardPage;
