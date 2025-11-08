import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const statusStyles = {
    In: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Out: 'bg-gray-500/10 text-gray-600 dark:bg-gray-500/20 dark:text-gray-400',
};

const VisitorDetailPage = () => {
    const { id } = useParams();
    const [visitor, setVisitor] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchVisitor = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('visitors')
                .select('*, students(full_name)')
                .eq('id', id)
                .single();

            if (error) {
                toast.error('Visitor log not found.');
            } else {
                setVisitor(data);
            }
            setLoading(false);
        };
        fetchVisitor();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!visitor) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Visitor log not found</div>;
    }

    return (
        <DetailPageLayout title={`Visitor: ${visitor.visitor_name}`} backTo="/visitors">
            <DetailItem label="Visitor Name" value={visitor.visitor_name} />
            <DetailItem label="Visiting Student" value={visitor.students.full_name} />
            <DetailItem label="Check-in Time" value={new Date(visitor.check_in_time).toLocaleString()} />
            <DetailItem label="Check-out Time" value={visitor.check_out_time ? new Date(visitor.check_out_time).toLocaleString() : 'N/A'} />
            <DetailItem label="Status">
                <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[visitor.status]}`}>
                    {visitor.status}
                </span>
            </DetailItem>
        </DetailPageLayout>
    );
};

export default VisitorDetailPage;
