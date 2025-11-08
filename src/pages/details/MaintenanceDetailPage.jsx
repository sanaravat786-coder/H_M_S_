import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const statusStyles = {
    Pending: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
    'In Progress': 'bg-blue-500/10 text-blue-600 dark:bg-blue-500/20 dark:text-blue-400',
    Resolved: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
};

const MaintenanceDetailPage = () => {
    const { id } = useParams();
    const [request, setRequest] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchRequest = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('maintenance_requests')
                .select('*, profiles:reported_by_id(full_name)')
                .eq('id', id)
                .single();

            if (error) {
                toast.error('Maintenance request not found.');
            } else {
                setRequest(data);
            }
            setLoading(false);
        };
        fetchRequest();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!request) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Maintenance request not found</div>;
    }

    return (
        <DetailPageLayout title={`Request: ${request.issue}`} backTo="/maintenance">
            <DetailItem label="Issue" value={request.issue} />
            <DetailItem label="Room Number" value={request.room_number} />
            <DetailItem label="Reported By" value={request.profiles?.full_name || 'N/A'} />
            <DetailItem label="Date Reported" value={new Date(request.created_at).toLocaleDateString()} />
            <DetailItem label="Status">
                <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[request.status]}`}>
                    {request.status}
                </span>
            </DetailItem>
        </DetailPageLayout>
    );
};

export default MaintenanceDetailPage;
