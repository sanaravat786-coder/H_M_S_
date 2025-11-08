import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const statusStyles = {
    Paid: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Due: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
    Overdue: 'bg-red-500/10 text-red-500 dark:bg-red-500/20 dark:text-red-400',
};

const FeeDetailPage = () => {
    const { id } = useParams();
    const [fee, setFee] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchFee = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('fees')
                .select('*, students(full_name)')
                .eq('id', id)
                .single();

            if (error) {
                toast.error('Fee record not found.');
            } else {
                setFee(data);
            }
            setLoading(false);
        };
        fetchFee();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!fee) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Fee record not found</div>;
    }

    return (
        <DetailPageLayout title={`Fee Record for ${fee.students.full_name}`} backTo="/fees">
            <DetailItem label="Student Name" value={fee.students.full_name} />
            <DetailItem label="Amount" value={`$${parseFloat(fee.amount).toFixed(2)}`} />
            <DetailItem label="Due Date" value={new Date(fee.due_date).toLocaleDateString()} />
            <DetailItem label="Status">
                <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[fee.status]}`}>
                    {fee.status}
                </span>
            </DetailItem>
            <DetailItem label="Payment Date" value={fee.status === 'Paid' && fee.payment_date ? new Date(fee.payment_date).toLocaleDateString() : 'N/A'} />
        </DetailPageLayout>
    );
};

export default FeeDetailPage;
