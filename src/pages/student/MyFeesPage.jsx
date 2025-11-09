import React, { useState, useEffect, useMemo } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';
import PageHeader from '../../components/ui/PageHeader';
import Modal from '../../components/ui/Modal';
import { Loader, User, Mail, BedDouble, Info, CreditCard } from 'lucide-react';
import toast from 'react-hot-toast';

const statusStyles = {
    Paid: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Due: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
    Overdue: 'bg-red-500/10 text-red-500 dark:bg-red-500/20 dark:text-red-400',
};

const MyFeesPage = () => {
    const { user } = useAuth();
    const [studentDetails, setStudentDetails] = useState(null);
    const [pendingFees, setPendingFees] = useState([]);
    const [paymentHistory, setPaymentHistory] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [selectedFee, setSelectedFee] = useState(null);
    const [formLoading, setFormLoading] = useState(false);

    useEffect(() => {
        const fetchData = async () => {
            if (!user) return;
            setLoading(true);
            try {
                const [profileRes, roomRes, feesRes, paymentsRes] = await Promise.all([
                    supabase.from('profiles').select('full_name, email').eq('id', user.id).single(),
                    supabase.from('room_allocations').select('rooms(room_number)').eq('student_id', user.id).eq('is_active', true).single(),
                    supabase.from('fees').select('*').eq('student_id', user.id).order('due_date', { ascending: true }),
                    supabase.from('payments').select('*, fees!inner(student_id)').eq('fees.student_id', user.id).order('paid_on', { ascending: false })
                ]);

                if (profileRes.error) throw profileRes.error;
                setStudentDetails({ ...profileRes.data, room_number: roomRes.data?.rooms?.room_number || 'N/A' });
                
                if (feesRes.error) throw feesRes.error;
                setPendingFees(feesRes.data.filter(f => f.status === 'Due' || f.status === 'Overdue'));

                if (paymentsRes.error) throw paymentsRes.error;
                setPaymentHistory(paymentsRes.data);

            } catch (error) {
                toast.error(`Failed to load fee details: ${error.message}`);
            } finally {
                setLoading(false);
            }
        };
        fetchData();
    }, [user]);

    const totalDue = useMemo(() => {
        return pendingFees.reduce((acc, fee) => acc + parseFloat(fee.amount), 0);
    }, [pendingFees]);

    const handlePayNow = (fee) => {
        setSelectedFee(fee);
        setIsModalOpen(true);
    };

    const handleConfirmPayment = async () => {
        if (!selectedFee) return;
        setFormLoading(true);
        try {
            const { error } = await supabase.rpc('process_fee_payment', { p_fee_id: selectedFee.id });
            if (error) throw error;
            toast.success('Payment successful!');
            // Refetch data
            const [feesRes, paymentsRes] = await Promise.all([
                supabase.from('fees').select('*').eq('student_id', user.id).order('due_date', { ascending: true }),
                supabase.from('payments').select('*, fees!inner(student_id)').eq('fees.student_id', user.id).order('paid_on', { ascending: false })
            ]);
            setPendingFees(feesRes.data.filter(f => f.status === 'Due' || f.status === 'Overdue'));
            setPaymentHistory(paymentsRes.data);
            setIsModalOpen(false);
        } catch (error) {
            toast.error(`Payment failed: ${error.message}`);
        } finally {
            setFormLoading(false);
        }
    };

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    return (
        <>
            <PageHeader title="Fee Payment" />
            
            <div className="space-y-8">
                {/* Student Details */}
                <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg">
                    <h2 className="text-xl font-bold mb-4">Student Details</h2>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                        <div className="flex items-center gap-3"><User className="w-5 h-5 text-primary"/> <div><span className="font-semibold">Name:</span> {studentDetails?.full_name}</div></div>
                        <div className="flex items-center gap-3"><Mail className="w-5 h-5 text-primary"/> <div><span className="font-semibold">Email:</span> {studentDetails?.email}</div></div>
                        <div className="flex items-center gap-3"><BedDouble className="w-5 h-5 text-primary"/> <div><span className="font-semibold">Room No:</span> {studentDetails?.room_number}</div></div>
                    </div>
                </div>

                {/* Pending Fees */}
                <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg">
                    <h2 className="text-xl font-bold mb-4">Pending Fees</h2>
                    <div className="overflow-x-auto">
                        <table className="min-w-full">
                            <thead className="border-b-2 border-base-200 dark:border-dark-base-300">
                                <tr>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Fee ID</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Due Date</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Amount</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Status</th>
                                    <th className="px-4 py-3 text-center text-xs font-medium text-base-content-secondary uppercase">Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                {pendingFees.length > 0 ? pendingFees.map(fee => (
                                    <tr key={fee.id} className="border-b border-base-200 dark:border-dark-base-300 last:border-0">
                                        <td className="px-4 py-4 text-sm font-mono text-base-content-secondary">{fee.id.substring(0, 8)}</td>
                                        <td className="px-4 py-4 text-sm">{new Date(fee.due_date).toLocaleDateString()}</td>
                                        <td className="px-4 py-4 text-sm font-semibold">${parseFloat(fee.amount).toFixed(2)}</td>
                                        <td className="px-4 py-4 text-sm"><span className={`px-2 py-1 text-xs font-semibold rounded-full ${statusStyles[fee.status]}`}>{fee.status}</span></td>
                                        <td className="px-4 py-4 text-center">
                                            <button onClick={() => handlePayNow(fee)} className="px-4 py-2 text-sm font-semibold text-primary-content bg-primary rounded-lg hover:bg-primary-focus transition">Pay Now</button>
                                        </td>
                                    </tr>
                                )) : (
                                    <tr><td colSpan="5" className="text-center py-8 text-base-content-secondary">No pending fees. Great job!</td></tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Payment History */}
                <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg">
                    <h2 className="text-xl font-bold mb-4">Payment History</h2>
                    <div className="overflow-x-auto">
                        <table className="min-w-full">
                             <thead className="border-b-2 border-base-200 dark:border-dark-base-300">
                                <tr>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Payment ID</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Payment Date</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Amount Paid</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-base-content-secondary uppercase">Fee ID</th>
                                </tr>
                            </thead>
                            <tbody>
                                {paymentHistory.length > 0 ? paymentHistory.map(payment => (
                                    <tr key={payment.id} className="border-b border-base-200 dark:border-dark-base-300 last:border-0">
                                        <td className="px-4 py-4 text-sm font-mono text-base-content-secondary">{payment.id.substring(0, 8)}</td>
                                        <td className="px-4 py-4 text-sm">{new Date(payment.paid_on).toLocaleString()}</td>
                                        <td className="px-4 py-4 text-sm font-semibold text-green-600">${parseFloat(payment.amount).toFixed(2)}</td>
                                        <td className="px-4 py-4 text-sm font-mono text-base-content-secondary">{payment.fee_id.substring(0, 8)}</td>
                                    </tr>
                                )) : (
                                    <tr><td colSpan="4" className="text-center py-8 text-base-content-secondary">No payment history found.</td></tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Total Due */}
                <div className="bg-primary/10 dark:bg-dark-primary/20 border-l-4 border-primary dark:border-dark-primary p-6 rounded-2xl flex justify-between items-center">
                    <h3 className="text-lg font-bold text-primary dark:text-dark-primary">Total Amount Due</h3>
                    <p className="text-3xl font-heading font-bold text-primary dark:text-dark-primary">${totalDue.toFixed(2)}</p>
                </div>
            </div>

            <Modal title="Confirm Payment" isOpen={isModalOpen} onClose={() => setIsModalOpen(false)}>
                {selectedFee && (
                    <div className="space-y-4">
                        <p>You are about to pay the following fee:</p>
                        <div className="bg-base-200 dark:bg-dark-base-300 p-4 rounded-lg space-y-2">
                            <div className="flex justify-between"><span className="font-semibold">Fee ID:</span> <span className="font-mono text-sm">{selectedFee.id.substring(0,8)}</span></div>
                            <div className="flex justify-between"><span className="font-semibold">Due Date:</span> <span>{new Date(selectedFee.due_date).toLocaleDateString()}</span></div>
                            <div className="flex justify-between text-lg"><span className="font-bold">Amount:</span> <span className="font-bold">${parseFloat(selectedFee.amount).toFixed(2)}</span></div>
                        </div>
                         <div className="p-4 bg-yellow-500/10 text-yellow-700 dark:text-yellow-300 rounded-lg flex items-start text-sm">
                            <Info className="w-5 h-5 mr-3 mt-0.5 flex-shrink-0" />
                            <p>This is a simulated payment. Clicking confirm will mark the fee as paid.</p>
                        </div>
                        <div className="flex justify-end pt-4 space-x-3">
                            <button type="button" onClick={() => setIsModalOpen(false)} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-lg text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                            <button
                                type="button"
                                onClick={handleConfirmPayment}
                                disabled={formLoading}
                                className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50"
                            >
                                {formLoading ? <Loader className="animate-spin h-4 w-4 mr-2" /> : <CreditCard className="h-4 w-4 mr-2" />}
                                Confirm Payment
                            </button>
                        </div>
                    </div>
                )}
            </Modal>
        </>
    );
};

export default MyFeesPage;
