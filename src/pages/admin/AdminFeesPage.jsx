import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import PageHeader from '../../components/ui/PageHeader';
import Modal from '../../components/ui/Modal';
import EmptyState from '../../components/ui/EmptyState';
import toast from 'react-hot-toast';
import { Loader, Edit, Trash2, CircleDollarSign } from 'lucide-react';

const statusStyles = {
    Paid: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Due: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
    Overdue: 'bg-red-500/10 text-red-500 dark:bg-red-500/20 dark:text-red-400',
};

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.05 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 10 },
    visible: { opacity: 1, y: 0 }
};

const AdminFeesPage = () => {
    const [fees, setFees] = useState([]);
    const [students, setStudents] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [formLoading, setFormLoading] = useState(false);
    const [currentFee, setCurrentFee] = useState(null);

    const fetchData = async () => {
        try {
            setLoading(true);
            const [feesResult, studentsResult] = await Promise.all([
                supabase
                    .from('fees')
                    .select('id, amount, due_date, status, payment_date, student_id, students(id, full_name)')
                    .order('due_date', { ascending: false }),
                supabase
                    .from('students')
                    .select('id, full_name')
                    .order('full_name')
            ]);
    
            if (feesResult.error) throw feesResult.error;
            if (studentsResult.error) throw studentsResult.error;
    
            setFees(feesResult.data || []);
            setStudents(studentsResult.data || []);
    
        } catch (error) {
            toast.error(`Failed to fetch data: ${error.message}`);
            console.error("Error fetching data:", error);
            setFees([]);
            setStudents([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
    }, []);

    const openAddModal = () => {
        setCurrentFee(null);
        setIsModalOpen(true);
    };

    const openEditModal = (fee) => {
        setCurrentFee(fee);
        setIsModalOpen(true);
    };

    const handleDelete = async (feeId) => {
        if (window.confirm('Are you sure you want to delete this fee record?')) {
            const { error } = await supabase.from('fees').delete().eq('id', feeId);
            if (error) {
                toast.error(error.message);
            } else {
                toast.success('Fee record deleted.');
                fetchData();
            }
        }
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setFormLoading(true);
        const formData = new FormData(e.target);
        const feeData = Object.fromEntries(formData.entries());
        
        const dataToSubmit = {
            ...feeData,
            payment_date: feeData.status === 'Paid' ? new Date().toISOString() : null,
        };

        let error;
        if (currentFee) {
            const { error: updateError } = await supabase.from('fees').update(dataToSubmit).eq('id', currentFee.id);
            error = updateError;
        } else {
            const { error: insertError } = await supabase.from('fees').insert([dataToSubmit]);
            error = insertError;
        }
        
        if (error) {
            toast.error(error.message);
        } else {
            toast.success(`Fee record ${currentFee ? 'updated' : 'added'} successfully!`);
            fetchData();
            setIsModalOpen(false);
        }
        setFormLoading(false);
    };

    return (
        <>
            <PageHeader
                title="Fee Management"
                buttonText="Add Fee Record"
                onButtonClick={openAddModal}
            />
            <div className="bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-lg overflow-hidden transition-colors">
                <div className="overflow-x-auto">
                    <table className="min-w-full">
                        <thead className="bg-base-200 dark:bg-dark-base-300">
                            <tr>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Student Name</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Amount</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Due Date</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Status</th>
                                <th className="px-6 py-4 text-right text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Actions</th>
                            </tr>
                        </thead>
                        {loading ? (
                            <tbody>
                                <tr><td colSpan="5" className="text-center py-10"><Loader className="mx-auto animate-spin" /></td></tr>
                            </tbody>
                        ) : fees.length > 0 ? (
                            <motion.tbody
                                className="divide-y divide-base-200 dark:divide-dark-base-300"
                                variants={containerVariants}
                                initial="hidden"
                                animate="visible"
                            >
                                {fees.map((fee) => (
                                    <motion.tr key={fee.id} className="hover:bg-base-200 dark:hover:bg-dark-base-300/50 transition-colors" variants={itemVariants}>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                                            <Link to={`/fees/${fee.id}`} className="text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">
                                                {fee.students?.full_name || 'N/A'}
                                            </Link>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{`$${parseFloat(fee.amount).toFixed(2)}`}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{new Date(fee.due_date).toLocaleDateString()}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm">
                                            <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[fee.status]}`}>
                                                {fee.status}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                            <button onClick={() => openEditModal(fee)} className="p-2 text-primary/70 hover:text-primary dark:text-dark-primary/70 dark:hover:text-dark-primary transition-colors">
                                                <Edit className="w-5 h-5" />
                                            </button>
                                            <button onClick={() => handleDelete(fee.id)} className="p-2 text-red-500/70 hover:text-red-500 dark:text-red-500/70 dark:hover:text-red-500 transition-colors">
                                                <Trash2 className="w-5 h-5" />
                                            </button>
                                        </td>
                                    </motion.tr>
                                ))}
                            </motion.tbody>
                        ) : (
                            <tbody>
                                <tr>
                                    <td colSpan="5">
                                        <EmptyState 
                                            icon={<CircleDollarSign className="w-full h-full" />}
                                            title="No Fee Records Found"
                                            message="Add a fee record to get started or check your database policies."
                                        />
                                    </td>
                                </tr>
                            </tbody>
                        )}
                    </table>
                </div>
            </div>
            <Modal title={currentFee ? 'Edit Fee Record' : 'Add Fee Record'} isOpen={isModalOpen} onClose={() => setIsModalOpen(false)}>
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label htmlFor="student_id" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Student</label>
                        <select id="student_id" name="student_id" defaultValue={currentFee?.student_id || ''} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                            <option value="">Select a student</option>
                            {students.map(s => <option key={s.id} value={s.id}>{s.full_name}</option>)}
                        </select>
                    </div>
                    <div>
                        <label htmlFor="amount" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Amount ($)</label>
                        <input type="number" name="amount" id="amount" step="0.01" defaultValue={currentFee?.amount || ''} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    <div>
                        <label htmlFor="due_date" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Due Date</label>
                        <input type="date" name="due_date" id="due_date" defaultValue={currentFee?.due_date ? new Date(currentFee.due_date).toISOString().split('T')[0] : ''} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    <div>
                        <label htmlFor="status" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Status</label>
                        <select id="status" name="status" defaultValue={currentFee?.status || 'Due'} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                            <option>Due</option>
                            <option>Paid</option>
                            <option>Overdue</option>
                        </select>
                    </div>
                    <div className="flex justify-end pt-4 space-x-3">
                        <button type="button" onClick={() => setIsModalOpen(false)} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-md text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                        <button type="submit" disabled={formLoading} className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50">
                            {formLoading && <Loader className="animate-spin h-4 w-4 mr-2" />}
                            {currentFee ? 'Save Changes' : 'Add Record'}
                        </button>
                    </div>
                </form>
            </Modal>
        </>
    );
};

export default AdminFeesPage;
