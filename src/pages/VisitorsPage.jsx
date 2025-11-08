import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import PageHeader from '../components/ui/PageHeader';
import Modal from '../components/ui/Modal';
import EmptyState from '../components/ui/EmptyState';
import toast from 'react-hot-toast';
import { Loader, LogOut, Trash2, UserCheck } from 'lucide-react';

const statusStyles = {
    In: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Out: 'bg-gray-500/10 text-gray-600 dark:bg-gray-500/20 dark:text-gray-400',
};

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.05 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 10 },
    visible: { opacity: 1, y: 0 }
};

const VisitorsPage = () => {
    const [visitors, setVisitors] = useState([]);
    const [students, setStudents] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [formLoading, setFormLoading] = useState(false);

    const fetchData = async () => {
        try {
            setLoading(true);
            const [visitorsResult, studentsResult] = await Promise.all([
                supabase
                    .from('visitors')
                    .select('id, visitor_name, student_id, check_in_time, check_out_time, status, students(id, full_name)')
                    .order('check_in_time', { ascending: false }),
                supabase
                    .from('students')
                    .select('id, full_name')
                    .order('full_name')
            ]);
    
            if (visitorsResult.error) throw visitorsResult.error;
            if (studentsResult.error) throw studentsResult.error;
    
            setVisitors(visitorsResult.data || []);
            setStudents(studentsResult.data || []);
    
        } catch (error) {
            toast.error(`Failed to fetch data: ${error.message}`);
            console.error("Error fetching data:", error);
            setVisitors([]);
            setStudents([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
    }, []);

    const handleAddVisitor = async (e) => {
        e.preventDefault();
        setFormLoading(true);
        const formData = new FormData(e.target);
        const { visitor_name, student_id } = Object.fromEntries(formData.entries());

        const { error } = await supabase.from('visitors').insert([{
            visitor_name,
            student_id,
            check_in_time: new Date().toISOString(),
            status: 'In',
        }]);

        if (error) {
            toast.error(error.message);
        } else {
            toast.success('New visitor logged successfully!');
            fetchData();
            setIsModalOpen(false);
        }
        setFormLoading(false);
    };

    const handleCheckOut = async (visitorId) => {
        const { error } = await supabase.from('visitors').update({
            status: 'Out',
            check_out_time: new Date().toISOString()
        }).eq('id', visitorId);

        if (error) {
            toast.error(error.message);
        } else {
            toast.success('Visitor checked out.');
            fetchData();
        }
    };

    const handleDelete = async (visitorId) => {
        if (window.confirm('Are you sure you want to delete this visitor log?')) {
            const { error } = await supabase.from('visitors').delete().eq('id', visitorId);
            if (error) {
                toast.error(error.message);
            } else {
                toast.success('Visitor log deleted.');
                fetchData();
            }
        }
    };

    return (
        <>
            <PageHeader
                title="Visitor Log"
                buttonText="Log Visitor"
                onButtonClick={() => setIsModalOpen(true)}
            />
            <div className="bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-lg overflow-hidden transition-colors">
                <div className="overflow-x-auto">
                    <table className="min-w-full">
                        <thead className="bg-base-200 dark:bg-dark-base-300">
                            <tr>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Visitor Name</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Visiting</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Check-in</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Check-out</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Status</th>
                                <th className="px-6 py-4 text-right text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Actions</th>
                            </tr>
                        </thead>
                        {loading ? (
                            <tbody>
                                <tr><td colSpan="6" className="text-center py-10"><Loader className="mx-auto animate-spin" /></td></tr>
                            </tbody>
                        ) : visitors.length > 0 ? (
                            <motion.tbody
                                className="divide-y divide-base-200 dark:divide-dark-base-300"
                                variants={containerVariants}
                                initial="hidden"
                                animate="visible"
                            >
                                {visitors.map((visitor) => (
                                    <motion.tr key={visitor.id} className="hover:bg-base-200 dark:hover:bg-dark-base-300/50 transition-colors" variants={itemVariants}>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                                            <Link to={`/visitors/${visitor.id}`} className="text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">{visitor.visitor_name}</Link>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{visitor.students?.full_name || 'N/A'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{new Date(visitor.check_in_time).toLocaleString()}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{visitor.check_out_time ? new Date(visitor.check_out_time).toLocaleString() : 'N/A'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm">
                                            <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[visitor.status]}`}>
                                                {visitor.status}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                                            {visitor.status === 'In' && (
                                                <button onClick={() => handleCheckOut(visitor.id)} className="p-2 text-yellow-600/70 hover:text-yellow-600 dark:text-yellow-400/70 dark:hover:text-yellow-400 transition-colors" title="Check Out">
                                                    <LogOut className="w-5 h-5" />
                                                </button>
                                            )}
                                            <button onClick={() => handleDelete(visitor.id)} className="p-2 text-red-500/70 hover:text-red-500 dark:text-red-500/70 dark:hover:text-red-500 transition-colors" title="Delete">
                                                <Trash2 className="w-5 h-5" />
                                            </button>
                                        </td>
                                    </motion.tr>
                                ))}
                            </motion.tbody>
                        ) : (
                           <tbody>
                                <tr>
                                    <td colSpan="6">
                                        <EmptyState 
                                            icon={<UserCheck className="w-full h-full" />}
                                            title="No Visitor Logs Found"
                                            message="Log a new visitor to get started or check your database policies."
                                        />
                                    </td>
                                </tr>
                            </tbody>
                        )}
                    </table>
                </div>
            </div>

            <Modal title="Log New Visitor" isOpen={isModalOpen} onClose={() => setIsModalOpen(false)}>
                <form onSubmit={handleAddVisitor} className="space-y-4">
                    <div>
                        <label htmlFor="visitor_name" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Visitor Name</label>
                        <input type="text" name="visitor_name" id="visitor_name" required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    <div>
                        <label htmlFor="student_id" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Visiting Student</label>
                        <select id="student_id" name="student_id" required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                            <option value="">Select a student</option>
                            {students.map(s => <option key={s.id} value={s.id}>{s.full_name}</option>)}
                        </select>
                    </div>
                    <div className="flex justify-end pt-4 space-x-3">
                        <button type="button" onClick={() => setIsModalOpen(false)} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-md text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                        <button type="submit" disabled={formLoading} className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50">
                            {formLoading && <Loader className="animate-spin h-4 w-4 mr-2" />}
                            Log Visitor
                        </button>
                    </div>
                </form>
            </Modal>
        </>
    );
};

export default VisitorsPage;
