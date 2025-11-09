import React from 'react';
import { useAuth } from '../context/AuthContext';
import AdminFeesPage from './admin/AdminFeesPage';
import MyFeesPage from './student/MyFeesPage';
import { Loader } from 'lucide-react';

const FeesPage = () => {
    const { user, loading } = useAuth();
    
    if (loading) {
        return (
            <div className="flex justify-center items-center h-full">
                <div className="flex items-center justify-center h-64">
                    <Loader className="animate-spin h-8 w-8 text-primary" />
                </div>
            </div>
        );
    }

    const userRole = user?.user_metadata?.role;

    if (userRole === 'Admin' || userRole === 'Staff') {
        return <AdminFeesPage />;
    }
    
    if (userRole === 'Student') {
        return <MyFeesPage />;
    }

    // Fallback for any other roles or if role is not defined
    return (
        <div className="text-center p-8">
            <h2 className="text-2xl font-bold">Access Denied</h2>
            <p className="text-base-content-secondary">You do not have permission to view this page.</p>
        </div>
    );
};

export default FeesPage;
