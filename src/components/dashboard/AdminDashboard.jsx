import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import StatCard from '../ui/StatCard';
import { Users, BedDouble, Wrench, CircleDollarSign, Loader, Megaphone } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';
import { Link } from 'react-router-dom';

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.1 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0 }
};

function AdminDashboard() {
    const [stats, setStats] = useState({
        totalStudents: 0,
        occupancyRate: 0,
        pendingMaintenance: 0,
        overdueFees: 0,
    });
    const [notices, setNotices] = useState([]);
    const [chartData, setChartData] = useState([]);
    const [recentPayments, setRecentPayments] = useState([]);
    const [loading, setLoading] = useState(true);
    const { user } = useAuth();

    useEffect(() => {
        const fetchDashboardData = async () => {
            setLoading(true);
            try {
                const [
                    studentsRes, roomsRes, maintenanceRes, feesRes,
                    noticesRes, paymentsRes, paidFeesRes
                ] = await Promise.all([
                    supabase.from('students').select('*', { count: 'exact', head: true }),
                    supabase.from('rooms').select('status'),
                    supabase.from('maintenance_requests').select('*', { count: 'exact', head: true }).eq('status', 'Pending'),
                    supabase.from('fees').select('*', { count: 'exact', head: true }).eq('status', 'Overdue'),
                    supabase.from('notices').select('id, title, created_at').limit(5).order('created_at', { ascending: false }),
                    supabase.from('payments').select('id, amount, paid_on, fees(students(full_name))').limit(5).order('paid_on', { ascending: false }),
                    supabase.from('fees').select('amount, created_at').eq('status', 'Paid')
                ]);

                // Process Stats
                const totalRooms = roomsRes.data?.length || 0;
                const occupiedRooms = roomsRes.data?.filter(r => r.status === 'Occupied').length || 0;
                setStats({
                    totalStudents: studentsRes.count || 0,
                    occupancyRate: totalRooms > 0 ? Math.round((occupiedRooms / totalRooms) * 100) : 0,
                    pendingMaintenance: maintenanceRes.count || 0,
                    overdueFees: feesRes.count || 0
                });

                // Process Notices
                setNotices(noticesRes.data || []);

                // Process Recent Payments
                setRecentPayments(paymentsRes.data || []);

                // Process Chart Data
                const monthlyCollections = (paidFeesRes.data || []).reduce((acc, fee) => {
                    const month = new Date(fee.created_at).toLocaleString('default', { month: 'short', year: '2-digit' });
                    acc[month] = (acc[month] || 0) + parseFloat(fee.amount);
                    return acc;
                }, {});

                const chartFormattedData = Object.keys(monthlyCollections).map(month => ({
                    name: month,
                    Collection: monthlyCollections[month],
                })).slice(-6); // Get last 6 months
                setChartData(chartFormattedData);

            } catch (error) {
                console.error("Error fetching dashboard data:", error);
            } finally {
                setLoading(false);
            }
        };

        fetchDashboardData();
    }, []);

    const renderValue = (value) => (loading ? <span className="text-2xl">...</span> : value);

    return (
        <motion.div initial="hidden" animate="visible" variants={containerVariants}>
            <motion.h1 className="text-3xl font-bold text-base-content dark:text-dark-base-content mb-6" variants={itemVariants}>
                Welcome back, {user?.user_metadata?.full_name || 'User'}!
            </motion.h1>
            <motion.div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6" variants={containerVariants}>
                <StatCard title="Total Students" value={renderValue(stats.totalStudents)} icon={<Users />} color="bg-blue-500" />
                <StatCard title="Occupancy Rate" value={renderValue(`${stats.occupancyRate}%`)} icon={<BedDouble />} color="bg-green-500" />
                <StatCard title="Pending Maintenance" value={renderValue(stats.pendingMaintenance)} icon={<Wrench />} color="bg-yellow-500" />
                <StatCard title="Overdue Fees" value={renderValue(stats.overdueFees)} icon={<CircleDollarSign />} color="bg-red-500" />
            </motion.div>

            <div className="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-8">
                <motion.div className="lg:col-span-2 bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg transition-colors" variants={itemVariants}>
                    <h2 className="text-xl font-semibold text-base-content dark:text-dark-base-content mb-4">Fee Collection</h2>
                    {loading ? <div className="flex items-center justify-center h-80"><Loader className="animate-spin" /></div> :
                        <ResponsiveContainer width="100%" height={320}>
                            <BarChart data={chartData} margin={{ top: 5, right: 20, left: -10, bottom: 5 }}>
                                <CartesianGrid strokeDasharray="3 3" stroke="currentColor" opacity={0.2} />
                                <XAxis dataKey="name" tick={{ fill: 'currentColor', fontSize: 12 }} />
                                <YAxis tick={{ fill: 'currentColor', fontSize: 12 }} tickFormatter={(value) => `$${value/1000}k`}/>
                                <Tooltip
                                    cursor={{ fill: 'rgba(128,128,128,0.1)' }}
                                    contentStyle={{
                                        backgroundColor: 'var(--tw-prose-bg, #fff)',
                                        border: '1px solid var(--tw-prose-invert-bg, #ddd)',
                                        borderRadius: '0.5rem'
                                    }}
                                />
                                <Legend />
                                <Bar dataKey="Collection" fill="var(--color-primary, #4f46e5)" />
                            </BarChart>
                        </ResponsiveContainer>
                    }
                </motion.div>

                <motion.div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg transition-colors" variants={itemVariants}>
                    <h2 className="text-xl font-semibold text-base-content dark:text-dark-base-content mb-4">Latest Notices</h2>
                    {loading ? <div className="flex items-center justify-center h-80"><Loader className="animate-spin" /></div> :
                        <ul className="space-y-4">
                            {notices.length > 0 ? notices.map(notice => (
                                <li key={notice.id} className="flex items-start space-x-3">
                                    <div className="flex-shrink-0 mt-1 p-1.5 bg-primary/10 text-primary rounded-full">
                                        <Megaphone className="w-4 h-4" />
                                    </div>
                                    <div>
                                        <Link to="/notices" className="text-sm font-semibold text-base-content dark:text-dark-base-content hover:underline">{notice.title}</Link>
                                        <p className="text-xs text-base-content-secondary dark:text-dark-base-content-secondary">{new Date(notice.created_at).toLocaleDateString()}</p>
                                    </div>
                                </li>
                            )) : <p className="text-sm text-center py-10 text-base-content-secondary dark:text-dark-base-content-secondary">No recent notices.</p>}
                        </ul>
                    }
                </motion.div>
            </div>

            <motion.div className="mt-8 bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg transition-colors" variants={itemVariants}>
                <h2 className="text-xl font-semibold text-base-content dark:text-dark-base-content mb-4">Recent Payments</h2>
                <div className="overflow-x-auto">
                    <table className="min-w-full">
                        <tbody>
                            {loading ? <tr><td colSpan="3" className="text-center py-10"><Loader className="animate-spin mx-auto" /></td></tr> :
                                recentPayments.length > 0 ? recentPayments.map(payment => (
                                    <tr key={payment.id} className="border-b border-base-200 dark:border-dark-base-300 last:border-0">
                                        <td className="py-3 pr-4 text-sm font-medium text-base-content dark:text-dark-base-content">{payment.fees?.students?.full_name || 'N/A'}</td>
                                        <td className="py-3 px-4 text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{new Date(payment.paid_on).toLocaleString()}</td>
                                        <td className="py-3 pl-4 text-sm font-semibold text-right text-green-600 dark:text-green-400">{`$${parseFloat(payment.amount).toFixed(2)}`}</td>
                                    </tr>
                                )) : <tr><td colSpan="3" className="text-center py-10 text-sm text-base-content-secondary dark:text-dark-base-content-secondary">No recent payments found.</td></tr>
                            }
                        </tbody>
                    </table>
                </div>
            </motion.div>
        </motion.div>
    );
}

export default AdminDashboard;
