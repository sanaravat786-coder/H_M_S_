import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { useAuth } from '../../context/AuthContext';
import { supabase } from '../../lib/supabase';
import { Link } from 'react-router-dom';
import { BedDouble, CircleDollarSign, Megaphone, Loader } from 'lucide-react';
import AttendanceMarker from './AttendanceMarker';

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.1 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0 }
};

const StudentDashboard = () => {
    const { user } = useAuth();
    const [summary, setSummary] = useState({
        roomNumber: 'N/A',
        pendingFees: 0,
        noticesCount: 0,
    });
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchSummary = async () => {
            if (!user) return;
            setLoading(true);
            try {
                const [roomRes, feesRes, noticesRes] = await Promise.all([
                    supabase.from('room_allocations').select('rooms(room_number)').eq('student_id', user.id).eq('is_active', true).maybeSingle(),
                    supabase.from('fees').select('*', { count: 'exact', head: true }).eq('student_id', user.id).in('status', ['Due', 'Overdue']),
                    supabase.from('notices').select('*', { count: 'exact', head: true }).in('audience', ['all', 'students'])
                ]);

                setSummary({
                    roomNumber: roomRes.data?.rooms?.room_number || 'Not Allocated',
                    pendingFees: feesRes.count || 0,
                    noticesCount: noticesRes.count || 0,
                });

            } catch (error) {
                console.error("Error fetching student summary:", error);
            } finally {
                setLoading(false);
            }
        };

        fetchSummary();
    }, [user]);

    return (
        <motion.div initial="hidden" animate="visible" variants={containerVariants}>
            <motion.h1 className="text-3xl font-bold text-base-content dark:text-dark-base-content mb-6" variants={itemVariants}>
                Welcome, {user?.user_metadata?.full_name || 'Student'}!
            </motion.h1>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                <motion.div variants={itemVariants} className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg flex items-center gap-4">
                    <div className="p-3 bg-blue-500/10 text-blue-500 rounded-full"><BedDouble size={24} /></div>
                    <div>
                        <p className="text-sm text-base-content-secondary">Your Room</p>
                        <p className="text-xl font-bold">{loading ? '...' : summary.roomNumber}</p>
                    </div>
                </motion.div>
                <motion.div variants={itemVariants} className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg flex items-center gap-4">
                    <div className="p-3 bg-red-500/10 text-red-500 rounded-full"><CircleDollarSign size={24} /></div>
                    <div>
                        <p className="text-sm text-base-content-secondary">Pending Fees</p>
                        <p className="text-xl font-bold">{loading ? '...' : summary.pendingFees}</p>
                    </div>
                    {summary.pendingFees > 0 && <Link to="/fees" className="ml-auto text-sm font-semibold text-primary hover:underline">Pay Now</Link>}
                </motion.div>
                <motion.div variants={itemVariants} className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg flex items-center gap-4">
                    <div className="p-3 bg-yellow-500/10 text-yellow-500 rounded-full"><Megaphone size={24} /></div>
                    <div>
                        <p className="text-sm text-base-content-secondary">Unread Notices</p>
                        <p className="text-xl font-bold">{loading ? '...' : summary.noticesCount}</p>
                    </div>
                    <Link to="/notices" className="ml-auto text-sm font-semibold text-primary hover:underline">View</Link>
                </motion.div>
            </div>

            <motion.div variants={itemVariants}>
                <AttendanceMarker />
            </motion.div>
        </motion.div>
    );
};

export default StudentDashboard;
